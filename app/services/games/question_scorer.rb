module Games
  # 문항 채점기 레지스트리(Phase 1 §1.2). question_type 4종을 서버 권위로 채점한다.
  # `QuestionScorer.for(question)` 팩토리가 타입별 채점기를 돌려주고, 각 채점기의
  # `score(response, hints_used:)` 는 항상 `{ score:, correct:, partial:, participation: }` 를 반환한다.
  #
  # 서버 채점·무유출 원칙(A.1 P5): 정답/정답키/힌트 공개수는 클라이언트로 위임하지 않는다.
  # 특히 hint_reveal 은 클라이언트가 주장하는 힌트수가 아니라 **서버가 넘겨준 hints_used**(§3.2b)
  # 로 차감한다 — 위조(다 보고 0개 주장)해도 서버값 기준이라 점수가 바뀌지 않는다.
  class QuestionScorer
    # 정답 1개(또는 쌍 1개)당 지급 포인트. QuizPlay 와 동일 스케일(만점 문항수×5).
    POINTS_PER_CORRECT = 5

    # question_type → 채점기 클래스.
    def self.for(question)
      scorer = REGISTRY.fetch(question.question_type) do
        raise ArgumentError, "지원하지 않는 question_type: #{question.question_type.inspect}"
      end
      scorer.new(question)
    end

    def initialize(question)
      @question = question
    end

    # 채점기 공통 계약. 서브클래스가 override 한다.
    def score(_response, hints_used: 0)
      raise NotImplementedError
    end

    protected

    def result(score:, correct: false, partial: false, participation: false)
      { score: score.to_i, correct: correct, partial: partial, participation: participation }
    end

    # mcq_single: 보기 인덱스 일치. correct? 하위호환 유지(nil/0 처리 동일).
    class McqSingle < QuestionScorer
      def score(response, hints_used: 0)
        ok = @question.correct?(response)
        result(score: ok ? POINTS_PER_CORRECT : 0, correct: ok, participation: !response.nil?)
      end
    end

    # mcq_multi: 정답 집합 대비 부분점수. (맞게 고른 수 − 틀리게 고른 수)/정답수 비율 × 만점.
    #
    # **만점은 정답 개수와 무관하게 문항당 POINTS_PER_CORRECT 다.** 예전에는 비율에
    # `correct_set.size` 를 곱해 정답 3개 문항의 만점이 15점(단일 정답의 3배)이었다. `PointAward`
    # 의 상한은 절대 상한이 아니라 "이 학생의 직전 최고치"(재플레이 파밍 방지용)라 이걸 막지
    # 못하므로, 교사가 정답을 여러 개 고르는 것만으로 판당 포인트가 몇 배인 퀴즈가 만들어졌다.
    # 문항 1개는 문항 1개다 — 어려움은 난이도이지 배점이 아니다.
    class McqMulti < QuestionScorer
      def score(response, hints_used: 0)
        correct_set = Array(@question.answer).map(&:to_i)
        selected = Array(response).map(&:to_i).uniq
        return result(score: 0) if correct_set.empty?

        hits = (selected & correct_set).size
        wrong = (selected - correct_set).size
        ratio = [ (hits - wrong).to_f / correct_set.size, 0.0 ].max
        exact = selected.sort == correct_set.sort
        points = (ratio * POINTS_PER_CORRECT).round

        result(
          score: points,
          correct: exact,
          partial: points.positive? && !exact,
          participation: selected.any?
        )
      end
    end

    # matching: 쌍맵 일치 개수 부분점수(쌍 1개당 POINTS_PER_CORRECT).
    class Matching < QuestionScorer
      def score(response, hints_used: 0)
        pairs = @question.answer.is_a?(Hash) ? @question.answer : {}
        submitted = response.is_a?(Hash) ? response : {}
        return result(score: 0) if pairs.empty?

        matched = pairs.count { |left, right| submitted[left.to_s].to_s == right.to_s }
        result(
          score: matched * POINTS_PER_CORRECT,
          correct: matched == pairs.size,
          partial: matched.positive? && matched < pairs.size,
          participation: submitted.any?
        )
      end
    end

    # hint_reveal: 정답 일치 AND 서버 힌트 공개수만큼 차감(C1 서버 권위). 최소 1점 보장.
    class HintReveal < QuestionScorer
      PENALTY_PER_HINT = 1

      def score(response, hints_used: 0)
        ok = normalize(response) == normalize(@question.answer)
        return result(score: 0, correct: false, participation: !response.nil?) unless ok

        points = [ POINTS_PER_CORRECT - hints_used.to_i * PENALTY_PER_HINT, 1 ].max
        result(score: points, correct: true, partial: hints_used.to_i.positive?, participation: true)
      end

      private

      def normalize(value)
        value.to_s.gsub(/\s+/, "").downcase
      end
    end

    REGISTRY = {
      "mcq_single" => McqSingle,
      "mcq_multi" => McqMulti,
      "matching" => Matching,
      "hint_reveal" => HintReveal
    }.freeze
  end
end
