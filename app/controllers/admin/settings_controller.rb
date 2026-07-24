# 시스템 설정(P7.4). feature_flags·default_rubric_weights·seasonal_banner 관리.
# API 키·시크릿류는 절대 저장하지 않는다(AppSetting 모델 가드 + 컨트롤러 필터).
class Admin::SettingsController < Admin::BaseController
  def show
    load_settings
  end

  def update
    @error = nil
    update_feature_flags
    update_rubric_weights
    AppSetting.set("seasonal_banner", params[:seasonal_banner].to_s.strip)
    store_custom_setting

    if @error
      load_settings
      flash.now[:alert] = @error
      render :show, status: :unprocessable_entity
    else
      redirect_to admin_settings_path, notice: notice_message
    end
  end

  private

  def load_settings
    @feature_flags = AppSetting.get("feature_flags", {})
    @rubric_weights = AppSetting.get("default_rubric_weights", ReadingDomain::DEFAULT_RUBRIC_WEIGHTS)
    @seasonal_banner = AppSetting.get("seasonal_banner", "")
  end

  def update_feature_flags
    raw = params[:feature_flags]
    return if raw.nil?

    parsed = parse_json_hash(raw)
    return if parsed.nil?

    # 민감 키(api key 류)는 기능 플래그로도 저장 금지 — 스크럽.
    scrubbed = parsed.reject { |name, _| AppSetting.sensitive_key?(name) }
    AppSetting.set("feature_flags", scrubbed)
  end

  def update_rubric_weights
    raw = params[:default_rubric_weights]
    return if raw.nil?

    parsed = parse_json_hash(raw)
    return if parsed.nil?

    AppSetting.set("default_rubric_weights", parsed)
  end

  # 이름·값 한 쌍의 임의 설정 추가. 민감 키는 모델 가드가 저장을 거부한다(무시).
  def store_custom_setting
    name = params[:setting_key].to_s.strip
    return if name.blank?

    unless AppSetting.set(name, params[:setting_value])
      @custom_rejected = true
    end
  end

  # JSON 텍스트를 해시로 파싱. 실패 시 @error 를 세우고 nil 반환(크래시 방지).
  def parse_json_hash(raw)
    stripped = raw.to_s.strip
    return {} if stripped.blank?

    parsed = JSON.parse(stripped)
    return parsed if parsed.is_a?(Hash)

    @error = "설정 값은 JSON 객체(해시) 형식이어야 합니다."
    nil
  rescue JSON::ParserError
    @error = "설정 값은 올바른 JSON 형식이어야 합니다."
    nil
  end

  def notice_message
    if @custom_rejected
      "설정을 저장했어요. (API 키류 항목은 보안상 저장하지 않았어요.)"
    else
      "시스템 설정을 저장했어요."
    end
  end
end
