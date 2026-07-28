require "test_helper"

# Phase 2b §2b.3 (C3) — 스코프형 기능 플래그. 전역 kill switch + 학급/학교 오버라이드로
# 한 학급 사고를 전교 off 없이 격리하고 파일럿→확대 롤아웃을 가능케 한다(교사 검수 부활 아님).
class AppSettingTest < ActiveSupport::TestCase
  FLAG = "on_demand_games".freeze

  setup do
    @school = School.create!(name: "플래그초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2)
  end

  def set_flags(hash)
    AppSetting.set("feature_flags", hash)
  end

  test "unset flag is fail-closed (off) globally and per scope" do
    set_flags({})
    assert_not AppSetting.feature_enabled?(FLAG)
    assert_not AppSetting.feature_enabled?(FLAG, scope: @room_a)
  end

  # 확대 모드 + 학급 스코프 격리: 전역 on, B반만 off → A on / B off(사고 격리).
  test "classroom scope isolates one classroom without affecting the other" do
    set_flags({ FLAG => true, "#{FLAG}:classroom:#{@room_b.id}" => false })

    assert AppSetting.feature_enabled?(FLAG, scope: @room_a), "A반은 전역 on 상속"
    assert_not AppSetting.feature_enabled?(FLAG, scope: @room_b), "B반은 스코프 off 로 격리"
  end

  # 파일럿 모드: 전역 미설정(기본 off), 파일럿 학급만 on.
  test "pilot mode enables only the opted-in classroom while global stays off" do
    set_flags({ "#{FLAG}:classroom:#{@room_a.id}" => true })

    assert AppSetting.feature_enabled?(FLAG, scope: @room_a), "파일럿 학급만 on"
    assert_not AppSetting.feature_enabled?(FLAG, scope: @room_b), "비파일럿 학급은 off"
    assert_not AppSetting.feature_enabled?(FLAG), "전역 기본은 off"
  end

  # 하드 kill: 전역 false → 스코프 on 오버라이드도 무시하고 전부 off.
  test "global kill switch (flag=false) forces off across all scopes, ignoring overrides" do
    set_flags({ FLAG => false, "#{FLAG}:classroom:#{@room_a.id}" => true })

    assert_not AppSetting.feature_enabled?(FLAG), "전역 off"
    assert_not AppSetting.feature_enabled?(FLAG, scope: @room_a), "스코프 on 이어도 하드 kill 이 우선"
  end

  # 학교 스코프: 학급 오버라이드가 없으면 학교 오버라이드를 적용.
  test "school scope override applies when no classroom override exists" do
    set_flags({ "#{FLAG}:school:#{@school.id}" => true })

    assert AppSetting.feature_enabled?(FLAG, scope: @room_a), "학급 오버라이드 없으면 학교 스코프 상속"
  end

  # User 를 scope 로 넘겨도 소속 학급/학교로 해석된다.
  test "a user scope resolves via its classroom then school" do
    student = User.create!(school: @school, classroom: @room_b, name: "플래그학생", password: "password")
    set_flags({ FLAG => true, "#{FLAG}:classroom:#{@room_b.id}" => false })

    assert_not AppSetting.feature_enabled?(FLAG, scope: student), "학생의 학급 오버라이드 반영"
  end

  # --- 보안(#5 우선): API 키·시크릿류 저장 차단 검증(credentials/ENV 전용 경계) ---

  # 이름 자체가 서비스명/키 접미사면 민감 키로 판정한다(대소문자·공백 무시).
  test "sensitive_key? flags provider names and key/secret/token suffixes" do
    %w[claude_api_key NAVER_CLIENT_SECRET data4library kakao_key session_token
       Claude api_secret].each do |name|
      assert AppSetting.sensitive_key?(name), "#{name} 는 민감 키로 차단돼야 한다"
    end
  end

  # 일반 설정 키는 통과한다(오탐 방지).
  test "sensitive_key? allows ordinary configuration keys" do
    %w[feature_flags default_rubric_weights seasonal_banner theme].each do |name|
      assert_not AppSetting.sensitive_key?(name), "#{name} 는 일반 설정이라 허용돼야 한다"
    end
  end

  # 모델 검증: 민감 키로 저장 시도 → invalid(모델 레벨 가드).
  test "a sensitive key fails validation and is not persisted" do
    setting = AppSetting.new(key: "claude_api_key", value: "leak")
    assert_not setting.valid?
    assert setting.errors[:key].any?
    assert_not AppSetting.new(key: "openai_secret", value: "x").valid?
  end

  # AppSetting.set 은 민감 키를 조용히 거부(false 반환)하고 저장하지 않는다.
  test "AppSetting.set refuses to store a sensitive key" do
    assert_equal false, AppSetting.set("naver_client_secret", "leak")
    assert_nil AppSetting.get("naver_client_secret")
  end

  # 일반 키는 정상 upsert.
  test "AppSetting.set stores an ordinary key" do
    assert AppSetting.set("theme", "dark")
    assert_equal "dark", AppSetting.get("theme")
  end
end
