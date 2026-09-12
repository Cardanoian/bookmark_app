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

  # 발견("이 책은 어때요?") 전용 밴드: game_band_for/guided_band_for 와 동형으로 학년 미상(nil/0)을
  # 최저 밴드(g12)로 고정한다(아동안전 — 학급 없는 학생에게 5~6학년 인기책을 기본 노출하지 않음).
  test "discovery_band_for fixes unknown grade to the lowest band (g12), mirroring game_band_for/guided_band_for" do
    assert_equal :g12, ReadingDomain.discovery_band_for(nil)
    assert_equal :g12, ReadingDomain.discovery_band_for(0)
    assert_equal :g12, ReadingDomain.discovery_band_for(1)
    assert_equal :g12, ReadingDomain.discovery_band_for(2)
    assert_equal :g34, ReadingDomain.discovery_band_for(3)
    assert_equal :g34, ReadingDomain.discovery_band_for(4)
    assert_equal :g56, ReadingDomain.discovery_band_for(5)
    assert_equal :g56, ReadingDomain.discovery_band_for(6)
  end

  # 학년군 → 정보나루 연령대 코드(loanItemSrch age 파라미터). 몬스터 스프라이트 빌드스크립트
  # BANDS 매핑(a8·a10·a12)과 일치해야 한다(§ ReadingDomain 헤더 주석).
  test "AGE_CODE_BY_BAND maps each band to its data4library age code" do
    assert_equal({ g12: "a8", g34: "a10", g56: "a12" }, ReadingDomain::AGE_CODE_BY_BAND)
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

  # 성취기준 allowlist: 학년군별 전체 목록이 해당 학년군 코드만 담고, 5축 대표 코드를 모두 포함한다.
  test "standards_allowlist contains only same-band codes and covers every representative axis code" do
    { g12: "2국", g34: "4국", g56: "6국" }.each do |band, prefix|
      allowlist = ReadingDomain.standards_allowlist(band)
      codes = allowlist.scan(/\[\d국\d{2}-\d{2}\]/)
      assert codes.any?, "#{band} allowlist 코드 없음"
      codes.each { |code| assert_includes code, prefix, "#{band} allowlist 타학년군 코드 누출: #{code}" }

      # 5축 대표 코드는 반드시 allowlist 의 부분집합이어야 첨삭이 목록 안에서만 인용 가능하다.
      ReadingDomain.achievement_standards(band).each_value do |rep|
        assert_includes codes, rep, "#{band} 대표 코드 #{rep} 가 allowlist 밖"
      end
    end
  end

  # ── 성취기준 원문 대조(교육부 고시 제2022-33호 [별책 5], 2026-09-13) ─────────────────────
  def curriculum_descriptions(band)
    ReadingDomain::CURRICULUM_STANDARDS_BY_BAND.fetch(band).values.flatten(1).to_h
  end

  # 원문: [4국05-01]=인물과 이야기의 흐름을 중심으로 감상, [4국05-02]=자신의 경험을 바탕으로 작품 속
  # 세계와 현실 세계를 비교. 이전 값은 두 설명이 원문과 달라 content·life 매핑이 뒤바뀌어 있었다.
  test "g34 content/life axes follow the official meaning of [4국05-01]/[4국05-02]" do
    codes = ReadingDomain.achievement_standards(:g34)
    descriptions = curriculum_descriptions(:g34)

    assert_equal "[4국05-01]", codes[:content], "내용 이해 축은 인물과 이야기의 흐름 기준"
    assert_equal "[4국05-02]", codes[:life], "삶과 연결 축은 경험 바탕 비교 기준"
    assert_equal "인물과 이야기의 흐름을 중심으로 작품을 감상한다.", descriptions.fetch("[4국05-01]")
    assert_equal "자신의 경험을 바탕으로 작품 속 세계와 현실 세계를 비교하여 작품을 감상한다.",
                 descriptions.fetch("[4국05-02]")
    assert_equal "감각적 표현에 유의하여 작품을 감상하고, 감각적 표현을 활용하여 자신의 생각이나 감정을 표현한다.",
                 descriptions.fetch(codes[:emotion])
  end

  # 원문 [6국05-06]은 "문학을 통해 자신과 삶을 성찰한다"(의역)가 아니다. 맞춤법 축은 문장 성분 호응
  # ([6국04-04])이 아니라 단어·문장·띄어쓰기를 바르게 고치는 [6국04-06](이전 목록에서 누락)이 맞다.
  test "g56 life/spelling axes use the official [6국05-06]/[6국04-06] sentences" do
    codes = ReadingDomain.achievement_standards(:g56)
    descriptions = curriculum_descriptions(:g56)

    assert_equal "[6국04-06]", codes[:spelling]
    assert_equal "글과 담화에 쓰인 단어 및 문장, 띄어쓰기를 민감하게 살펴 바르게 고치는 태도를 지닌다.",
                 descriptions.fetch("[6국04-06]")
    assert_equal "[6국05-06]", codes[:life]
    assert_equal "작품을 읽고 자신의 삶과 연관 지어 성찰하는 태도를 지닌다.", descriptions.fetch("[6국05-06]")
  end

  # 고시의 영역별 성취기준 개수 스냅샷 — 코드가 빠지거나(이전 [6국04-06] 누락) 없는 코드가 끼면 실패한다.
  test "allowlist domains hold exactly the official number of consecutive codes" do
    official_counts = {
      g12: { "읽기" => 5, "쓰기" => 4, "문법" => 3, "문학" => 4 },
      g34: { "읽기" => 6, "쓰기" => 5, "문법" => 5, "문학" => 5 },
      g56: { "읽기" => 5, "쓰기" => 6, "문법" => 6, "문학" => 6 }
    }
    domain_no = { "읽기" => "02", "쓰기" => "03", "문법" => "04", "문학" => "05" }

    official_counts.each do |band, counts|
      grade = { g12: 2, g34: 4, g56: 6 }.fetch(band)
      domains = ReadingDomain::CURRICULUM_STANDARDS_BY_BAND.fetch(band)
      assert_equal counts.keys, domains.keys, "#{band} 영역 구성"
      counts.each do |domain, count|
        expected = (1..count).map { |n| format("[%d국%s-%02d]", grade, domain_no.fetch(domain), n) }
        assert_equal expected, domains.fetch(domain).map(&:first), "#{band}/#{domain} 코드 목록"
      end
    end
  end

  # 성취기준.md 는 상수의 앱 안 사본이다. 한쪽만 고치면 "출처" 문서와 프롬프트 allowlist 가 갈린다.
  test "성취기준.md carries the same sentences as CURRICULUM_STANDARDS_BY_BAND" do
    md = Rails.root.join("app/views/monsters/성취기준.md").read
    md_sentences = md.scan(/- (\[\d국\d{2}-\d{2}\]) (.+)$/).to_h

    ReadingDomain::BANDS.each do |band|
      curriculum_descriptions(band).each do |code, description|
        assert_equal description, md_sentences[code], "#{code} 문장이 성취기준.md 와 다름"
      end
    end
  end

  # ── 학생 대면 첨삭 규칙(베타 리뷰 지적 1~5) ────────────────────────────────────────
  CHILD_FACING_RULE_BLOCKS = %i[
    REVIEW_NON_ATTEMPT_RULES REVIEW_GROUNDING_RULES BOOK_FACT_RULES CHILD_VOICE_RULES REVIEW_EXAMPLE
  ].freeze

  test "rubric_prompt carries every child-facing rule block for every band" do
    ReadingDomain::BANDS.each do |band|
      prompt = ReadingDomain.rubric_prompt(band)

      CHILD_FACING_RULE_BLOCKS.each do |name|
        assert_includes prompt, ReadingDomain.const_get(name), "#{band} 프롬프트에 #{name} 누락"
      end
      assert_includes prompt, ReadingDomain.build_feedback_limit_rules(band), "#{band} 개수 상한 누락"
    end
  end

  # 규칙 블록의 핵심 문장 — 문구가 흐려져 규칙이 사라지는 회귀를 막는다.
  test "child-facing rule blocks state the concrete rules reviewers asked for" do
    # 1) 원문 그대로 인용 + 지적 전 자기 점검 + 같은 문장 제안 삭제
    grounding = ReadingDomain::REVIEW_GROUNDING_RULES
    assert_includes grounding, "학생이 쓴 그대로 옮기세요"
    assert_includes grounding, "한 글자도 바꾸지 말고"
    assert_includes grounding, "이미 마침표(.)로 나뉜 문장이면 나누자고 하지 마세요"
    assert_includes grounding, "학생이 쓴 문장과 같거나 거의 같으면 그 항목은 빼세요"
    assert_includes grounding, "어디인지(인용), 왜 고치면 좋은지(까닭), 무엇을 하면 되는지(할 일 한 가지)"

    # 2) 무의미 입력 → 칭찬 없음·최저점·다시 써 달라는 부탁 하나, 서툰 진짜 글은 예외
    gate = ReadingDomain::REVIEW_NON_ATTEMPT_RULES
    assert_includes gate, "자음·모음만 늘어놓은 글"
    assert_includes gate, "'테스트테스트테스트'"
    assert_includes gate, "책과 분명히 관계없는 글"
    assert_includes gate, "독후감이 아니면 칭찬하지 마세요"
    assert_includes gate, "praise 와 grow 는 빈 배열 []"
    assert_includes gate, "rubric 다섯 축은 모두 0점"
    assert_includes gate, "짧거나 맞춤법이 많이 틀려도 책에 대해 쓰려고 한 흔적이 있으면 독후감입니다"

    # 3) 호칭 금지·해요체 일관·쉬운 말
    voice = ReadingDomain::CHILD_VOICE_RULES
    assert_includes voice, "'당신', '학생', '귀하'"
    assert_includes voice, "부르는 말 없이 바로 말하세요"
    assert_includes voice, "해요체로만"
    assert_includes voice, "합쇼체"
    assert_includes voice, "이 지시문의 말투를 따라 하지 마세요"

    # 4) 책 내용 단정 금지 — 질문으로 묻기
    facts = ReadingDomain::BOOK_FACT_RULES
    assert_includes facts, "줄거리·인물 이름·사건·결말을 사실처럼 쓰지 마세요"
    assert_includes facts, "질문으로 물어보세요"
    assert_includes facts, "'어떤 장면에서 그렇게 느꼈나요?'"
  end

  # 무의미 입력 게이트는 채점 지시보다 앞에 와야 모델이 먼저 걸러낸다. 규칙·예시는 JSON 스키마 앞.
  test "rubric_prompt puts the non-attempt gate before scoring and the writing rules before the schema" do
    ReadingDomain::BANDS.each do |band|
      prompt = ReadingDomain.rubric_prompt(band)
      gate_at = prompt.index(ReadingDomain::REVIEW_NON_ATTEMPT_RULES)
      scoring_at = prompt.index("다음 5개 축을 각각 0~5의 정수로 채점하세요.")
      schema_at = prompt.index("반드시 아래 JSON 스키마만 반환")

      assert gate_at < scoring_at, "#{band} 게이트가 채점 지시 뒤에 있음"
      assert prompt.index(ReadingDomain::REVIEW_EXAMPLE) < schema_at, "#{band} 예시가 스키마 뒤에 있음"
      assert prompt.index(ReadingDomain::CHILD_VOICE_RULES) < schema_at, "#{band} 말투 규칙이 스키마 뒤에 있음"
    end
  end

  # 5) 한 번에 한두 가지 — fix·grow 상한. g12 는 tone "고칠 점은 딱 한 가지만"과 같은 1개.
  test "feedback limits keep suggestions to one or two and match the g12 tone" do
    assert_equal ReadingDomain::BANDS.sort, ReadingDomain::FEEDBACK_LIMITS_BY_BAND.keys.sort
    ReadingDomain::FEEDBACK_LIMITS_BY_BAND.each do |band, limits|
      assert_includes 1..2, limits[:fix], "#{band} fix 상한"
      assert_includes 1..2, limits[:grow], "#{band} grow 상한"

      rules = ReadingDomain.build_feedback_limit_rules(band)
      assert_includes rules, "fix 는 최대 #{limits[:fix]}개, grow 는 최대 #{limits[:grow]}개"
      assert_includes rules, "가장 중요한 것부터"
      assert_includes rules, "fix 와 grow 에 같은 내용을 되풀이하지 마세요"
    end

    assert_equal 1, ReadingDomain.feedback_limits(:g12)[:fix]
    assert_includes ReadingDomain::PROMPT_META[:g12][:tone], "고칠 점은 딱 한 가지만"
    assert_equal ReadingDomain.feedback_limits(:g56), ReadingDomain.feedback_limits(:nope), "미지원 band → g56"
  end

  # 새 규칙 블록은 학년군 무관 상수라 세 밴드 프롬프트에 모두 들어간다 — 코드가 섞이면 누출 가드를 우회한다.
  test "child-facing rule blocks never contain 성취기준 codes" do
    blocks = CHILD_FACING_RULE_BLOCKS.map { |name| ReadingDomain.const_get(name) }
    blocks += ReadingDomain::BANDS.map { |band| ReadingDomain.build_feedback_limit_rules(band) }
    blocks.each { |text| refute_match(/\[\d국\d{2}-\d{2}\]/, text) }
  end

  # 뷰·교사 편집이 의존하는 응답 스키마는 그대로여야 한다.
  test "rubric_prompt keeps the response JSON schema unchanged" do
    ReadingDomain::BANDS.each do |band|
      prompt = ReadingDomain.rubric_prompt(band)
      rep = ReadingDomain.achievement_standards(band)[:life]

      assert_includes prompt, '"level": "A|B|C"'
      assert_includes prompt, '"rubric": { "content": 0, "emotion": 0, "life": 0, "structure": 0, "spelling": 0 }'
      assert_includes prompt, '"praise": ["잘한 점 문장"]'
      assert_includes prompt, '"fix": ["보완하면 좋을 점 문장"]'
      assert_includes prompt, %("grow": [ { "text": "성장 제안 문장", "standard_code": "#{rep}" } ])
      assert_includes prompt, '"pts": 0'
    end
  end

  # 학년 눈높이 봉쇄(핵심 회귀 가드): 3학년에게 6학년 성취기준을 제시하는 문제 방지.
  # 각 밴드 프롬프트는 자기 밴드 allowlist 만 담고, 다른 학년군의 브래킷 성취기준 코드는 절대 포함하지 않는다.
  test "rubric_prompt embeds the band allowlist and never references another band's 성취기준 codes" do
    { g12: "2국", g34: "4국", g56: "6국" }.each do |band, prefix|
      prompt = ReadingDomain.rubric_prompt(band)

      # allowlist 블록이 프롬프트에 통째로 주입된다.
      assert_includes prompt, ReadingDomain.standards_allowlist(band), "#{band} allowlist 미주입"
      # 목록 밖 코드 사용 금지 지시가 있다.
      assert_includes prompt, "목록 안의 코드만 사용", "#{band} allowlist 제약 지시 누락"

      # 다른 학년군의 성취기준 코드(브래킷 표기)는 단 하나도 없어야 한다.
      %w[2국 4국 6국].reject { |p| p == prefix }.each do |other|
        refute_match(/\[#{other}\d{2}-\d{2}\]/, prompt, "#{band} 프롬프트에 타학년군 코드(#{other}) 누출")
      end
    end
  end

  # 등급 인플레이션 차단(핵심 회귀 가드): 앵커 없이 "0~5로 채점하라"만 주면 LLM 이 거의 모든
  # 축에 4를 줘서 5축 평균이 A 문턱을 넘고 전원 A 가 된다(실측: Gemini 축평균 4.37·맞춤법 축
  # 표준편차 0.00). 앵커 블록과 "기본값 3점" 지시가 세 밴드 프롬프트에 모두 살아 있어야 한다.
  test "rubric_prompt injects per-axis score anchors and the 3점 기본값 rule for every band" do
    ReadingDomain::BANDS.each do |band|
      prompt = ReadingDomain.rubric_prompt(band)

      assert_includes prompt, "[축별 점수 기준]", "#{band} 앵커 블록 누락"
      assert_includes prompt, "3점이 이 학년군에서 기대하는 보통 수준", "#{band} 기본값 3점 지시 누락"
      assert_includes prompt, "등급을 먼저 정한 뒤 축 점수를 거꾸로 맞추지 마세요", "#{band} 역산 금지 지시 누락"

      ReadingDomain::RUBRIC_AXES.each do |axis|
        anchors = ReadingDomain::RUBRIC_SCORE_ANCHORS.fetch(axis)
        [ 5, 3, 1 ].each do |score|
          assert_includes prompt, "#{score}점: #{anchors.fetch(score)}",
            "#{band}/#{axis} #{score}점 앵커 누락"
        end
      end
    end
  end

  # 앵커는 학년군 무관 상수라 성취기준 코드를 담으면 세 밴드 프롬프트 모두에 그 코드가 새어
  # 들어가 "타학년군 코드 누출" 가드를 우회한다. 앵커 자체에 코드가 없어야 한다.
  test "rubric score anchors never contain 성취기준 codes" do
    ReadingDomain::RUBRIC_SCORE_ANCHORS.each do |axis, anchors|
      anchors.each_value do |text|
        refute_match(/\[\d국\d{2}-\d{2}\]/, text, "#{axis} 앵커에 성취기준 코드 포함")
      end
    end
  end

  # 임계값 드리프트 가드: 프롬프트가 안내하는 등급 규칙과 앱이 실제로 매기는 등급이 갈리면,
  # 모델은 A 기준이라 믿은 점수를 줬는데 학생은 B 를 받는 상황이 조용히 생긴다.
  test "LEVEL_RULE renders the same thresholds RubricScorable actually applies" do
    assert_includes ReadingDomain::LEVEL_RULE, ReadingDomain::LEVEL_A_MIN_LIFE.to_s
    assert_includes ReadingDomain::LEVEL_RULE, ReadingDomain::LEVEL_A_MIN_AVG.to_s
    assert_includes ReadingDomain::LEVEL_RULE, ReadingDomain::LEVEL_B_MIN_AVG.to_s

    a_min = ReadingDomain::LEVEL_A_MIN_AVG
    life_min = ReadingDomain::LEVEL_A_MIN_LIFE
    b_min = ReadingDomain::LEVEL_B_MIN_AVG

    assert_equal "A", RubricScorable.level_for(a_min, life_min)
    assert_equal "B", RubricScorable.level_for(a_min, life_min - 1), "life 게이트 미달인데 A"
    assert_equal "B", RubricScorable.level_for(b_min, life_min)
    assert_equal "C", RubricScorable.level_for(b_min - 0.1, life_min)
  end

  # 가중치 기본값은 ReadingDomain 단일 진실. Classroom 이 리터럴로 되돌아가면 신규 학급의
  # rubric_config 와 가중치 미설정 학급의 채점 기준이 갈린다.
  test "Classroom default rubric weights alias the ReadingDomain constant" do
    assert_same ReadingDomain::DEFAULT_RUBRIC_WEIGHTS, Classroom::DEFAULT_RUBRIC_WEIGHTS
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
