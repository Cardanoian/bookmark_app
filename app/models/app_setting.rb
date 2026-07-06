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

  # 기능 플래그 조회. feature_flags 설정(JSON 해시)에서 flag 의 truthy 여부를 반환한다.
  def self.feature_enabled?(flag)
    flags = get("feature_flags", {})
    return false unless flags.is_a?(Hash)

    !!flags[flag.to_s]
  end

  private

  def key_must_not_be_sensitive
    return unless self.class.sensitive_key?(key)

    errors.add(:key, "API 키·시크릿류는 설정에 저장할 수 없습니다")
  end
end
