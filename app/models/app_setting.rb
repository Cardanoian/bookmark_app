# 전역 시스템 설정(P7.4). key 로 조회하는 단일 진실. value 는 JSON.
# API 키·시크릿류는 절대 저장하지 않는다(credentials/ENV 전용) — 모델 레벨 가드.
class AppSetting < ApplicationRecord
  # 저장 금지 키 패턴: gemini/kakao/naver/data4library 를 포함하거나
  # *_api_key / *_key / *_secret / *_token 으로 끝나는 이름(대소문자 무시).
  SENSITIVE_NAME = /(gemini|kakao|naver|data4library)/i
  SENSITIVE_SUFFIX = /(_api_key|_key|_secret|_token)\z/i

  validates :key, presence: true, uniqueness: true
  validate :key_must_not_be_sensitive

  # 이름이 API 키/시크릿류로 보이면 true(저장 금지 대상).
  def self.sensitive_key?(name)
    normalized = name.to_s.strip.downcase
    return false if normalized.blank?

    normalized.match?(SENSITIVE_NAME) || normalized.match?(SENSITIVE_SUFFIX)
  end

  # 설정 값 조회. 없으면 default. (value 는 JSON 그대로 반환)
  def self.get(key, default = nil)
    record = find_by(key: key.to_s)
    record ? record.value : default
  end

  # 설정 값 저장(upsert). 민감 키는 저장을 거부하고 false 를 반환한다.
  def self.set(key, value)
    return false if sensitive_key?(key)

    record = find_or_initialize_by(key: key.to_s)
    record.value = value
    record.save
  end

  # 스코프형 기능 플래그 조회(Phase 2b §2b.3, C3). feature_flags 설정(JSON 해시)에서
  # flag 의 truthy 여부를 학급/학교 스코프까지 반영해 반환한다. 전역 boolean 하나가 아니라
  # 학급/학교별 오버라이드를 두어 **한 학급의 사고를 전교 off 없이 격리**하고,
  # **파일럿→확대 롤아웃**을 가능케 한다(교사 검수 게이트 부활 아님, R4 준수).
  #
  # feature_flags(JSON) 저장 규약 — flag = "on_demand_games" 예시:
  #   "on_demand_games"                => 전역 값. **false = 하드 kill 스위치**(스코프 오버라이드도
  #                                       무시하고 전부 off), 미설정(nil) = 파일럿 모드(기본 off,
  #                                       스코프 on 오버라이드만 켜짐), true = 확대 모드(기본 on,
  #                                       스코프 off 오버라이드로 개별 학급만 격리).
  #   "on_demand_games:classroom:<id>" => 학급 스코프 오버라이드(전역보다 우선. 단, 하드 kill 예외).
  #   "on_demand_games:school:<id>"    => 학교 스코프 오버라이드(학급 오버라이드 다음 우선).
  #
  # 롤아웃 시나리오:
  #   파일럿   : "on_demand_games" 미설정 + "on_demand_games:classroom:5" => true (5반만 온디맨드)
  #   확대     : "on_demand_games" => true (전체 on), 문제 학급만 "on_demand_games:classroom:9" => false
  #   전면중단 : "on_demand_games" => false (스코프 무시, 전부 오프라인 강등)
  #
  # scope 는 Classroom / School / User(classroom·school 소속) 아무거나 받는다(없으면 전역만).
  def self.feature_enabled?(flag, scope: nil)
    flags = get("feature_flags", {})
    return false unless flags.is_a?(Hash)

    key = flag.to_s
    global = flags[key]
    return false if global == false # 하드 kill — 스코프 오버라이드도 무시

    override = scope_flag(flags, key, scope)
    return !!override unless override.nil?

    !!global
  end

  private_class_method def self.scope_flag(flags, key, scope)
    return nil if scope.nil?

    scope_ids_for(scope).each do |kind, id|
      next if id.nil?

      scoped_key = "#{key}:#{kind}:#{id}"
      return flags[scoped_key] if flags.key?(scoped_key)
    end
    nil
  end

  # scope 객체에서 (학급 우선, 학교 다음) 오버라이드 조회 순서를 만든다. 학급이 더 구체적이라 먼저.
  private_class_method def self.scope_ids_for(scope)
    classroom_id = scope.is_a?(Classroom) ? scope.id : scope.try(:classroom_id) || scope.try(:classroom)&.id
    school_id    = scope.is_a?(School)    ? scope.id : scope.try(:school_id)    || scope.try(:school)&.id
    [ [ "classroom", classroom_id ], [ "school", school_id ] ]
  end

  private

  def key_must_not_be_sensitive
    return unless self.class.sensitive_key?(key)

    errors.add(:key, "API 키·시크릿류는 설정에 저장할 수 없습니다")
  end
end
