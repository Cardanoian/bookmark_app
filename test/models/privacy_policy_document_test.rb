require "test_helper"

class PrivacyPolicyDocumentTest < ActiveSupport::TestCase
  SAMPLE = <<~MD.freeze
    <!--
    운영자 메모: 서버 133.186.251.153
    -->

    # 「책갈피」 개인정보 처리방침

    머리말 첫 줄
    이어지는 줄

    ## 목차

    - 제1조 첫째 조
    - 부록 1 첫째 부록

    ### 제1조(첫째 조)

    | 구분 | 내용 |
    | ---- | ---- |
    | 학생 | 이름<br>학교 |

    1. 파기 절차
    2. 파기 방법
       1) 전자 파일
       2) 종이

    <!-- 본문 사이 메모 -->

    ## 부록 1. 첫째 부록

    1. 활용 범위

    | 기능 |
    | ---- |
    | AI 첨삭 |

    2. 이용하는 AI

    3. 보내지 않는 정보

    ---
  MD

  def blocks
    @blocks ||= PrivacyPolicyDocument.parse(SAMPLE)
  end

  # 원본 첫머리 주석에는 운영자 메모·서버 주소가 있다. 화면은 제목 줄부터 시작해야 한다.
  test "parsing starts at the title line and drops HTML comments" do
    assert_equal PrivacyPolicyDocument::Heading.new(level: 1, text: "「책갈피」 개인정보 처리방침", anchor: nil), blocks.first
    rendered_text = blocks.inspect
    assert_not_includes rendered_text, "133.186.251.153"
    assert_not_includes rendered_text, "본문 사이 메모"
  end

  test "a source without the title line fails loudly instead of publishing the editor notes" do
    assert_raises(ArgumentError) { PrivacyPolicyDocument.parse("<!-- 메모 -->\n\n# 다른 제목\n") }
  end

  # 주석을 지우기 전에 제목을 찾으면, 머리 주석 안에 제목 줄을 인용한 메모가 공개된다(리뷰에서 재현).
  test "a title line quoted inside the editor notes does not leak the rest of the notes" do
    source = "<!--\n#{PrivacyPolicyDocument::TITLE}\n서버 1.2.3.4 메모\n-->\n\n#{PrivacyPolicyDocument::TITLE}\n\n본문\n"

    parsed = PrivacyPolicyDocument.parse(source)

    assert_not_includes parsed.inspect, "1.2.3.4"
    assert_equal PrivacyPolicyDocument::Paragraph.new(text: "본문"), parsed.last
  end

  test "an unclosed HTML comment fails instead of publishing what follows it" do
    assert_raises(ArgumentError) { PrivacyPolicyDocument.parse("#{PrivacyPolicyDocument::TITLE}\n\n<!-- 비공개 메모 1.2.3.4\n") }
  end

  test "CRLF line endings and trailing spaces on the title line still parse" do
    parsed = PrivacyPolicyDocument.parse("#{PrivacyPolicyDocument::TITLE} \r\n\r\n본문\r\n")

    assert_equal [ "「책갈피」 개인정보 처리방침", "본문" ], parsed.map(&:text)
  end

  test "only the row right after the header counts as the table separator" do
    table = PrivacyPolicyDocument.parse("#{PrivacyPolicyDocument::TITLE}\n\n| 구분 | 값 |\n| --- | --- |\n| - | - |\n").last

    assert_equal [ [ "-", "-" ] ], table.rows
  end

  test "consecutive lines join into one paragraph" do
    assert_equal PrivacyPolicyDocument::Paragraph.new(text: "머리말 첫 줄 이어지는 줄"), blocks[1]
  end

  test "headings carry article and appendix anchors and the table of contents list is flagged" do
    headings = blocks.grep(PrivacyPolicyDocument::Heading)
    assert_equal [ nil, nil, "article-1", "appendix-1" ], headings.map(&:anchor)

    toc = blocks.grep(PrivacyPolicyDocument::ListBlock).find(&:toc)
    assert_equal [ "제1조 첫째 조", "부록 1 첫째 부록" ], toc.items.map(&:text)
    assert_equal 1, blocks.grep(PrivacyPolicyDocument::ListBlock).count(&:toc)
  end

  test "tables skip the separator row and keep cell text for inline rendering" do
    table = blocks.grep(PrivacyPolicyDocument::Table).first
    assert_equal [ "구분", "내용" ], table.header
    assert_equal [ [ "학생", "이름<br>학교" ] ], table.rows
  end

  test "indented 1) items nest under the preceding item with their marker kept" do
    list = blocks.grep(PrivacyPolicyDocument::ListBlock).find { |block| block.items.first.text == "파기 절차" }
    assert list.ordered
    assert_equal [ "파기 절차", "파기 방법" ], list.items.map(&:text)
    assert_equal [ "1) 전자 파일", "2) 종이" ], list.items.last.children
  end

  # 부록 1 처럼 "1." 뒤에 표가 끼고 "2." 부터 빈 줄을 사이에 둔 항목은 번호를 이어 한 목록이 된다.
  test "ordered items separated by blank lines stay one list and keep their starting number" do
    lists = blocks.grep(PrivacyPolicyDocument::ListBlock).select(&:ordered).last(2)
    assert_equal [ 1, [ "활용 범위" ] ], [ lists.first.start, lists.first.items.map(&:text) ]
    assert_equal [ 2, [ "이용하는 AI", "보내지 않는 정보" ] ], [ lists.last.start, lists.last.items.map(&:text) ]
    assert_instance_of PrivacyPolicyDocument::Rule, blocks.last
  end

  # 실제 원본: 목차의 모든 항목이 화면 안의 제목으로 이어져야 한다(조를 추가·삭제하면 목차도 함께).
  test "every table of contents entry in the real policy links to a heading on the page" do
    real = PrivacyPolicyDocument.parse(File.read(PrivacyPolicyDocument::SOURCE_PATH))
    anchors = real.grep(PrivacyPolicyDocument::Heading).filter_map(&:anchor)
    toc = real.grep(PrivacyPolicyDocument::ListBlock).find(&:toc)

    assert_equal (1..17).map { "article-#{_1}" } + %w[appendix-1 appendix-2], anchors
    assert_equal anchors, toc.items.map { PrivacyPolicyDocument.anchor_for(_1.text) }
  end

  # 해석기가 모르는 문법(https 가 아닌 링크·인용·4단계 제목·주석)을 공개본에 쓰면 기호째 화면에 나간다 —
  # 쓰기 전에 해석기를 고친다. https 링크는 PrivacyPoliciesHelper 가 그린다.
  test "the published policy uses only syntax the parser understands" do
    source = File.read(PrivacyPolicyDocument::SOURCE_PATH)

    assert_no_match(/\]\(/, source.gsub(PrivacyPoliciesHelper::POLICY_INLINE_PATTERN, ""), "https 가 아닌 마크다운 링크")
    assert_no_match(/^\s*>/, source, "인용")
    assert_no_match(/^####/, source, "4단계 이상 제목")
    assert_no_match(/<!--|-->/, source, "HTML 주석 — 공개본에는 메모를 두지 않는다")
  end

  # 편집 원본(docs/ 중첩 저장소)은 개발기에만 있다 — CI·배포 이미지에는 없으므로 그때는 대조할 대상이 없다.
  # 있으면 공개본이 편집 원본의 제목 줄부터와 같아야 한다. 다르면 `bin/rails privacy_policy:publish` 를 돌린다.
  test "the published copy matches the editor original when the original is present" do
    return unless File.exist?(PrivacyPolicyDocument::EDITOR_SOURCE_PATH)

    expected = PrivacyPolicyDocument.public_text(File.read(PrivacyPolicyDocument::EDITOR_SOURCE_PATH))
    assert_equal expected, File.read(PrivacyPolicyDocument::SOURCE_PATH),
      "docs/PRIVACY_POLICY.md 가 바뀌었습니다 — bin/rails privacy_policy:publish 로 config/privacy_policy.md 를 다시 만드세요"
  end
end
