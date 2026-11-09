# 개인정보 처리방침 화면(privacy_policies#show)의 내용.
#
# 원본은 두 벌이다.
# - 편집 원본 docs/PRIVACY_POLICY.md — 첫머리 HTML 주석에 운영자 메모(미확정 쟁점·서버 주소)가 있다.
#   docs/ 는 바깥 저장소가 무시하는 중첩 git 저장소라 Kamal(git clone 빌드)·CI·제출본에 들어가지 않는다.
# - 공개본 config/privacy_policy.md — 편집 원본의 **제목 줄(TITLE)부터**, HTML 주석을 지운 것.
#   앱은 이것만 읽는다. `bin/rails privacy_policy:publish` 가 편집 원본에서 다시 만들고, 편집 원본이 있는
#   개발기에서는 두 벌이 다르면 테스트가 실패한다(test/models/privacy_policy_document_test.rb).
#
# 이름을 PrivacyPolicy 로 두지 않은 까닭: Pundit 이 `authorize :privacy` 를 PrivacyPolicy 클래스로 찾는다.
#
# 마크다운 해석기는 이 문서가 쓰는 문법만 다룬다(제목 #~###, 문단, `-`·`1.` 목록과 그 아래
# 들여쓴 `1)` 항목, 표, `---`) + 인라인(굵게 `**`, https 링크 `[글자](https://…)`, 표 칸 안의 `<br>` —
# PrivacyPoliciesHelper#policy_inline). 문서에 새 문법을 쓰면 여기를 함께 고친다.
class PrivacyPolicyDocument
  EDITOR_SOURCE_PATH = Rails.root.join("docs/PRIVACY_POLICY.md")
  SOURCE_PATH = Rails.root.join("config/privacy_policy.md")
  TITLE = "# 「책갈피」 개인정보 처리방침".freeze

  Heading = Data.define(:level, :text, :anchor)
  Paragraph = Data.define(:text)
  # toc: 「목차」 제목 아래 목록 — 항목을 해당 조·부록 제목으로 가는 링크로 그린다.
  ListBlock = Data.define(:ordered, :start, :items, :toc)
  # children: 들여쓴 `1)` 항목. 표시 기호를 글자에 남긴다(법령식 번호 체계 ①·1.·1) 유지).
  ListItem = Data.define(:text, :children)
  Table = Data.define(:header, :rows)
  Rule = Data.define

  # production 은 부팅할 때 한 번 읽는다(config/initializers/privacy_policy.rb) — 공개본이 없거나 깨졌으면
  # 이미지 빌드(assets:precompile)에서 멈추고, 헬스체크는 통과했는데 버튼만 500 인 배포가 생기지 않는다.
  def self.blocks
    if Rails.env.development?
      parse(File.read(SOURCE_PATH))
    else
      @blocks ||= parse(File.read(SOURCE_PATH))
    end
  end

  def self.parse(markdown)
    Parser.new(public_text(markdown)).parse
  end

  # 공개해도 되는 부분만 돌려준다: 줄바꿈을 맞추고, HTML 주석을 **문서 전체에서 먼저** 지운 뒤 제목 줄부터.
  # 제목을 먼저 찾으면 머리 주석 안에 제목 줄을 인용한 메모가 공개된다. 닫히지 않은 주석·제목 줄 없음은
  # 메모째 내보내지 않도록 실패시킨다. 그래서 본문에는 `<!--`·`-->` 를 글자로 쓰지 않는다(화살표는 →).
  def self.public_text(markdown)
    text = markdown.gsub(/\r\n?/, "\n").gsub(/<!--.*?-->/m, "")
    raise ArgumentError, "개인정보 처리방침 원본에 닫히지 않은 HTML 주석이 있습니다" if text.include?("<!--") || text.include?("-->")

    start = text.index(/^#{Regexp.escape(TITLE)}[ \t]*$/) or
      raise ArgumentError, "개인정보 처리방침 원본에 제목 줄(#{TITLE})이 없습니다"
    text[start..]
  end

  # 조·부록 제목과 목차 항목이 같은 앵커를 쓴다. "제7조(…)"·"제7조 …" → article-7, "부록 1…" → appendix-1.
  def self.anchor_for(text)
    case text
    when /\A제(\d+)조/ then "article-#{$1}"
    when /\A부록 (\d+)/ then "appendix-#{$1}"
    end
  end

  class Parser
    TABLE_SEPARATOR = /\A\|[\s:|-]+\|\z/

    def initialize(markdown)
      @lines = markdown.lines(chomp: true)
      @blocks = []
      @paragraph = []
      @list = nil
      @table = nil
      @section = nil
    end

    def parse
      @lines.each { |line| consume(line) }
      flush_all
      @blocks
    end

    private

    def consume(line)
      case line
      when /\A\s*\z/
        # 빈 줄은 문단·표를 끝내지만 목록은 이어 둔다 — "2. …" 와 "3. …" 사이에 빈 줄이 있어도 한 목록이다.
        flush_paragraph
        flush_table
      when /\A(\#{1,3}) (.+)\z/
        flush_all
        @section = $2.strip
        @blocks << Heading.new(level: $1.size, text: @section, anchor: PrivacyPolicyDocument.anchor_for(@section))
      when /\A-{3,}\z/
        flush_all
        @blocks << Rule.new
      when /\A\|/
        flush_paragraph
        flush_list
        add_table_row(line)
      when /\A- (.+)\z/
        add_list_item($1, ordered: false)
      when /\A(\d+)\. (.+)\z/
        add_list_item($2, ordered: true, number: $1.to_i)
      when /\A\s+(\d+\) .+)\z/
        if @list
          @list[:items].last.children << $1
        else
          add_paragraph_line(line.strip)
        end
      else
        add_paragraph_line(line.strip)
      end
    end

    def add_paragraph_line(text)
      flush_table
      flush_list
      @paragraph << text
    end

    def add_list_item(text, ordered:, number: 1)
      flush_paragraph
      flush_table
      flush_list if @list && @list[:ordered] != ordered
      @list ||= { ordered: ordered, start: number, items: [], toc: @section == "목차" }
      @list[:items] << ListItem.new(text: text, children: [])
    end

    def add_table_row(line)
      # 구분 줄(| --- |)은 머리 줄 바로 다음에만 있다 — 칸이 모두 -·: 인 데이터 행을 지우지 않게 그 자리에서만 건너뛴다.
      if @table && !@table[:separated] && @table[:rows].empty? && line.match?(TABLE_SEPARATOR)
        @table[:separated] = true
        return
      end

      cells = line.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip)
      if @table
        @table[:rows] << cells
      else
        @table = { header: cells, rows: [], separated: false }
      end
    end

    def flush_all
      flush_paragraph
      flush_table
      flush_list
    end

    def flush_paragraph
      return if @paragraph.empty?

      @blocks << Paragraph.new(text: @paragraph.join(" "))
      @paragraph = []
    end

    def flush_table
      return unless @table

      @blocks << Table.new(header: @table[:header], rows: @table[:rows])
      @table = nil
    end

    def flush_list
      return unless @list

      @blocks << ListBlock.new(**@list)
      @list = nil
    end
  end
end
