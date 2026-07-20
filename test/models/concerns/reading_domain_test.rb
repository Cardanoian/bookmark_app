require "test_helper"

# 학년군(band) 분기: 5축 성취기준·프롬프트·추천활동이 1~2/3~4/5~6학년군으로
# 나뉘고, 학년 미상은 5~6학년군으로 폴백해 기존 동작을 보존하는지 검증한다.
class ReadingDomainTest < ActiveSupport::TestCase
  test "band_for maps grade to the correct 학년군, defaulting unknown to g56" do
    assert_equal :g12, ReadingDomain.band_for(1)
    assert_equal :g12, ReadingDomain.band_for(2)
    assert_equal :g34, ReadingDomain.band_for(3)
    assert_equal :g34, ReadingDomain.band_for(4)
    assert_equal :g56, ReadingDomain.band_for(5)
    assert_equal :g56, ReadingDomain.band_for(6)
    assert_equal :g56, ReadingDomain.band_for(nil)
    assert_equal :g56, ReadingDomain.band_for(0)
  end

  # 게임 전용 밴드: band_for 와 달리 학년 미상(nil/0)을 **최저 밴드(g12)** 로 고정한다
  # (5~6학년 콘텐츠 기본 매칭·밴드 경계 느슨함 제거, TODO 후속 정밀화). 명시 학년은 band_for 동일.
  test "game_band_for fixes unknown grade to the lowest band (g12) while band_for keeps g56" do
    assert_equal :g12, ReadingDomain.game_band_for(nil), "학년 미상은 최저 밴드로 고정"
    assert_equal :g12, ReadingDomain.game_band_for(0)
    assert_equal :g12, ReadingDomain.game_band_for(1)
    assert_equal :g34, ReadingDomain.game_band_for(3)
    assert_equal :g56, ReadingDomain.game_band_for(5)
    assert_equal :g56, ReadingDomain.game_band_for(6)
    # 첨삭·다학년 대시보드가 쓰는 band_for 는 여전히 미상=g56 로 기존 동작 보존(회귀 가드).
    assert_equal :g56, ReadingDomain.band_for(nil)
  end

  test "each band exposes all five axes with band-appropriate 성취기준 code prefixes" do
    { g12: "2국", g34: "4국", g56: "6국" }.each do |band, prefix|
      codes = ReadingDomain.achievement_standards(band)
      assert_equal ReadingDomain::RUBRIC_AXES.sort, codes.keys.sort, "#{band} 축 누락"
      codes.each_value do |code|
        assert_match(/\A\[#{prefix}\d{2}-\d{2}\]\z/, code, "#{band} 코드 형식/학년군 불일치: #{code}")
      end
    end
  end

  test "recommended_activities cover every axis per band" do
    ReadingDomain::BANDS.each do |band|
      activities = ReadingDomain.recommended_activities(band)
      assert_equal ReadingDomain::RUBRIC_AXES.sort, activities.keys.sort
      activities.each_value { |text| assert text.present? }
    end
  end

  test "rubric_prompt injects the band grade label and its 성취기준 codes" do
    {
      g12: [ "초등학교 1~2학년", "[2국02-03]" ],
      g34: [ "초등학교 3~4학년", "[4국05-01]" ],
      g56: [ "초등학교 5~6학년", "[6국05-03]" ]
    }.each do |band, (label, code)|
      prompt = ReadingDomain.rubric_prompt(band)
      assert_includes prompt, label
      assert_includes prompt, code
    end
  end

  test "quizgen_prompt reflects the band grade label" do
    assert_includes ReadingDomain.quizgen_prompt(:g12), "초등학교 1~2학년"
    assert_includes ReadingDomain.quizgen_prompt(:g34), "초등학교 3~4학년"
    assert_includes ReadingDomain.quizgen_prompt(:g56), "초등학교 5~6학년"
  end

  test "ocr prompt removes layout line breaks while preserving intentional paragraphs" do
    prompt = ReadingDomain::OCR_PROMPT

    assert_includes prompt, "행 끝 줄바꿈은 문단 구분이 아니므로 없애고"
    assert_includes prompt, "한 단어가 갈라졌다면 공백 없이"
    assert_includes prompt, "일부러 나눈 문단"
    assert_includes prompt, "들여쓰기해서 시작한 줄"
    assert_includes prompt, "빈 줄 하나(\\n\\n)"
    assert_includes prompt, "맞춤법이나 문장을 임의로 고치지 말고"
  end

  test "flat constants remain the 5~6학년군 default for backward compatibility" do
    assert_equal ReadingDomain.achievement_standards(:g56), ReadingDomain::ACHIEVEMENT_STANDARDS
    assert_equal ReadingDomain.recommended_activities(:g56), ReadingDomain::RECOMMENDED_ACTIVITIES
    assert_equal ReadingDomain.rubric_prompt(:g56), ReadingDomain::RUBRIC_PROMPT
    assert_equal ReadingDomain.quizgen_prompt(:g56), ReadingDomain::QUIZGEN_PROMPT
  end

  test "unknown band falls back to the g56 default rather than raising" do
    assert_equal ReadingDomain.achievement_standards(:g56), ReadingDomain.achievement_standards(:nope)
    assert_equal ReadingDomain.rubric_prompt(:g56), ReadingDomain.rubric_prompt(:nope)
    assert_equal ReadingDomain.recommended_activities(:g56), ReadingDomain.recommended_activities(:nope)
    assert_equal ReadingDomain.quizgen_prompt(:g56), ReadingDomain.quizgen_prompt(:nope)
  end

  test "prompts are frozen and built once" do
    assert ReadingDomain.rubric_prompt(:g34).frozen?
    assert_same ReadingDomain.rubric_prompt(:g34), ReadingDomain.rubric_prompt(:g34)
  end

  # Phase 2a: content_axis별 콘텐츠 프롬프트 — band 성취기준·눈높이 + 축별 JSON 스키마 키 +
  # count/해설/오답 지시가 3 content_axis × 3 band 모두에 주입되는지(스냅샷) 검증한다.
  # 게임 재구성 Phase 1: matching(vocab) 생성 경로 제거 → CONTENT_PROMPTS 에서 matching 빠짐.
  AXIS_SCHEMA_KEYS = {
    mcq: %w[questions choices answer_index explanation],
    hint_reveal: %w[targets hints answer]
  }.freeze

  test "build_content_prompt injects band standard, axis schema keys, count/해설/오답 rules for all bands×axes" do
    ReadingDomain::BANDS.each do |band|
      label = ReadingDomain::PROMPT_META.fetch(band)[:grade_label]
      content_code = ReadingDomain.achievement_standards(band)[:content]

      AXIS_SCHEMA_KEYS.each do |axis, keys|
        prompt = ReadingDomain.content_prompt(band, axis)
        assert_includes prompt, label, "#{band}/#{axis} 눈높이 라벨 누락"
        assert_includes prompt, content_code, "#{band}/#{axis} 성취기준 코드 누락"
        assert_includes prompt, ReadingDomain::CONTENT_COUNTS[axis].to_s, "#{band}/#{axis} count 강제 누락"
        assert_includes prompt, "해설", "#{band}/#{axis} 해설 강제 지시 누락"
        assert_includes prompt, "오답", "#{band}/#{axis} 오답 품질 지시 누락"
        assert_includes prompt, "난이도", "#{band}/#{axis} 난이도 티어 지시 누락"
        keys.each { |key| assert_includes prompt, key, "#{band}/#{axis} 스키마 키 #{key} 누락" }
      end
    end
  end

  test "content_prompt is prebuilt, frozen, and falls back for unknown band/axis" do
    assert ReadingDomain.content_prompt(:g34, :mcq).frozen?
    assert_same ReadingDomain.content_prompt(:g34, :mcq), ReadingDomain.content_prompt(:g34, :mcq)
    assert_equal ReadingDomain.content_prompt(:g56, :mcq), ReadingDomain.content_prompt(:nope, :mcq)
    assert_equal ReadingDomain.content_prompt(:g56, :mcq), ReadingDomain.content_prompt(:g56, :nope)
  end

  test "content_prompt differs across bands for the same axis" do
    AXIS_SCHEMA_KEYS.each_key do |axis|
      refute_equal ReadingDomain.content_prompt(:g12, axis), ReadingDomain.content_prompt(:g56, axis), "#{axis} band 미분화"
    end
  end
end
