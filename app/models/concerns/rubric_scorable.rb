# Computes A/B/C 등급·포인트 from a 5축 루브릭 해시. Included into Report, but the
# core `score_rubric`/`level_for` are also exposed as module functions so services
# (RuleBasedReview 등) can reuse the exact same logic without an AR instance.
module RubricScorable
  extend ActiveSupport::Concern

  class << self
    # rubric_hash: { content:, emotion:, life:, structure:, spelling: } (0..5, 누락축→0).
    # weights: 축별 가중치 해시(기본 동일 가중치).
    # 반환: { avg:, level:, points: }.
    def score_rubric(rubric_hash, weights: ReadingDomain::DEFAULT_RUBRIC_WEIGHTS)
      scores = rubric_hash.to_h.symbolize_keys
      weight_map = weights.to_h.symbolize_keys

      weighted_sum = 0.0
      weight_total = 0.0
      ReadingDomain::RUBRIC_AXES.each do |axis|
        weight = (weight_map[axis] || 0).to_f
        weighted_sum += (scores[axis] || 0).to_f * weight
        weight_total += weight
      end

      avg = weight_total.zero? ? 0.0 : (weighted_sum / weight_total).round(2)
      level = level_for(avg, (scores[:life] || 0).to_f)
      { avg: avg, level: level, points: ReadingDomain::LEVEL_POINTS.fetch(level) }
    end

    # A: 가중평균 4.0 이상 AND 삶 4 이상. B: 가중평균 2.5 이상. 그 외 C.
    def level_for(avg, life)
      if avg >= 4.0 && life >= 4
        "A"
      elsif avg >= 2.5
        "B"
      else
        "C"
      end
    end
  end

  class_methods do
    def score_rubric(rubric_hash, weights: ReadingDomain::DEFAULT_RUBRIC_WEIGHTS)
      RubricScorable.score_rubric(rubric_hash, weights: weights)
    end
  end

  # 5축 해시로 self.rubric/avg/level 을 채운다(저장은 호출자 책임). 학급 가중치 반영.
  # 반환: { avg:, level:, points: } (호출자가 포인트 지급에 사용).
  def apply_rubric!(rubric_hash)
    weights = classroom_rubric_weights
    result = RubricScorable.score_rubric(rubric_hash, weights: weights)

    self.rubric = rubric_hash
    self.avg = result[:avg]
    self.level = result[:level]
    result
  end

  private

  def classroom_rubric_weights
    return ReadingDomain::DEFAULT_RUBRIC_WEIGHTS unless respond_to?(:classroom)

    classroom&.rubric_weights || ReadingDomain::DEFAULT_RUBRIC_WEIGHTS
  end
end
