require "zip"

module Exports
  # 표 한 장짜리 최소 XLSX 워크북을 손으로 만든다. 외부 젬(caxlsx 등) 없이 rubyzip 만 쓰며,
  # 읽기 쪽 `Recommendations::XlsxReader` 와 같은 방침이다(ZIP 컨테이너 + 소량의 XML 파트).
  #
  # **CSV 대신 XLSX 를 내보내는 이유**
  #  - 수식 주입이 구조적으로 막힌다. 문자열 셀(`t="inlineStr"`)은 엑셀이 수식으로 해석하지 않아
  #    `=HYPERLINK("http://…","눌러보세요")` 같은 학생 입력 제목이 텍스트로 남는다. 같은 값이
  #    CSV 에서는 파일을 여는 순간 수식이 된다(`'` 접두 같은 꼼수가 필요했다).
  #  - 인코딩 협상이 없다. 한글 깨짐 방지용 UTF-8 BOM 을 앞에 붙이던 관행이 사라진다.
  #  - 점수가 텍스트가 아니라 숫자로 들어가 정렬·평균·차트가 바로 된다.
  #  - 제목의 쉼표·따옴표를 이스케이프할 일이 없다(값이 XML 요소 안에 통째로 들어간다).
  #
  # 지원 범위는 의도적으로 좁다 — 시트 1장, 굵은 머리글 1줄, 문자열/숫자 셀, 열 너비, 틀 고정.
  # 수식·병합·서식·이미지는 넣지 않는다(필요해지면 그때 젬 도입을 다시 판단한다).
  class XlsxWriter
    MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main".freeze
    REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships".freeze
    PACKAGE_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships".freeze
    CONTENT_TYPES_NS = "http://schemas.openxmlformats.org/package/2006/content-types".freeze

    CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

    # 시트 이름은 31자 제한이고 : \ / ? * [ ] 를 쓸 수 없다(엑셀이 파일을 못 연다).
    SHEET_NAME_FORBIDDEN = %r{[\[\]:*?/\\]}
    SHEET_NAME_LIMIT = 31

    # XML 1.0 이 허용하지 않는 제어문자. 남겨 두면 엑셀이 "복구가 필요한 파일"이라며 연다.
    INVALID_XML_CHARS = /[\x00-\x08\x0B\x0C\x0E-\x1F]/

    MIN_COLUMN_WIDTH = 8
    MAX_COLUMN_WIDTH = 44

    def self.build(...) = new(...).build

    # headers: 머리글 한 줄(굵게 + 틀 고정). rows: 값 배열의 배열(nil 은 빈 칸).
    def initialize(headers:, rows:, sheet_name: "Sheet1")
      @headers = headers.to_a
      @rows = rows.to_a
      @sheet_name = sanitize_sheet_name(sheet_name)
    end

    # 반환: xlsx 파일 바이트(바이너리 문자열).
    def build
      buffer = Zip::OutputStream.write_buffer(StringIO.new(String.new)) do |zip|
        write(zip, "[Content_Types].xml", content_types_xml)
        write(zip, "_rels/.rels", root_relationships_xml)
        write(zip, "xl/workbook.xml", workbook_xml)
        write(zip, "xl/_rels/workbook.xml.rels", workbook_relationships_xml)
        write(zip, "xl/styles.xml", styles_xml)
        write(zip, "xl/worksheets/sheet1.xml", worksheet_xml)
      end
      buffer.string
    end

    private

    attr_reader :headers, :rows, :sheet_name

    def write(zip, name, contents)
      zip.put_next_entry(name)
      zip.write(contents)
    end

    def sanitize_sheet_name(name)
      cleaned = name.to_s.gsub(SHEET_NAME_FORBIDDEN, " ").squish
      cleaned = "Sheet1" if cleaned.empty?
      cleaned[0, SHEET_NAME_LIMIT]
    end

    # ── 워크북 뼈대 ────────────────────────────────────────────────────────────

    def content_types_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="#{CONTENT_TYPES_NS}">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="#{CONTENT_TYPE}.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
      XML
    end

    def root_relationships_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="#{PACKAGE_REL_NS}">
          <Relationship Id="rId1" Type="#{REL_NS}/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
      XML
    end

    def workbook_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="#{MAIN_NS}" xmlns:r="#{REL_NS}">
          <sheets><sheet name="#{escape(sheet_name)}" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
      XML
    end

    def workbook_relationships_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="#{PACKAGE_REL_NS}">
          <Relationship Id="rId1" Type="#{REL_NS}/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="#{REL_NS}/styles" Target="styles.xml"/>
        </Relationships>
      XML
    end

    # 스타일은 두 개뿐이다 — 0=기본, 1=굵게(머리글).
    # fills 는 2개를 채운다: 엑셀이 0=none, 1=gray125 를 전제하고 열기 때문이다.
    def styles_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="#{MAIN_NS}">
          <fonts count="2">
            <font><sz val="11"/><name val="Calibri"/></font>
            <font><b/><sz val="11"/><name val="Calibri"/></font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1"><border/></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="2">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
          </cellXfs>
          <!-- 이름 있는 기본 스타일. 없으면 일부 리더가 "기본 스타일이 없다"고 경고한다. -->
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
      XML
    end

    # ── 시트 ──────────────────────────────────────────────────────────────────

    # 요소 순서(sheetViews → cols → sheetData)를 지켜야 엑셀이 파일을 연다.
    def worksheet_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="#{MAIN_NS}">
          #{frozen_header_xml}
          #{columns_xml}
          <sheetData>#{sheet_rows_xml}</sheetData>
        </worksheet>
      XML
    end

    # 머리글이 있으면 첫 줄을 고정해 스크롤해도 열 이름이 보이게 한다.
    def frozen_header_xml
      return "" if headers.empty?

      %(<sheetViews><sheetView workbookViewId="0">) +
        %(<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>) +
        %(</sheetView></sheetViews>)
    end

    def columns_xml
      widths = column_widths
      return "" if widths.empty?

      cols = widths.each_with_index.map do |width, index|
        %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>)
      end
      "<cols>#{cols.join}</cols>"
    end

    # 한글은 폭이 라틴 문자의 두 배쯤이라 2로 센다(엑셀 열 너비는 '문자 수' 단위).
    def column_widths
      all_rows = ([ headers ] + rows).reject(&:nil?)
      column_count = all_rows.map(&:size).max.to_i
      return [] if column_count.zero?

      Array.new(column_count) do |index|
        longest = all_rows.filter_map { |row| display_width(row[index]) }.max.to_i
        longest.clamp(MIN_COLUMN_WIDTH - 2, MAX_COLUMN_WIDTH - 2) + 2
      end
    end

    def display_width(value)
      return 0 if value.nil?

      value.to_s.each_char.sum { |char| char.bytesize > 1 ? 2 : 1 }
    end

    def sheet_rows_xml
      all_rows = headers.empty? ? rows : [ headers ] + rows
      all_rows.each_with_index.map do |values, index|
        style = (index.zero? && !headers.empty?) ? 1 : 0
        row_xml(values, index + 1, style)
      end.join
    end

    def row_xml(values, row_number, style)
      cells = values.to_a.each_with_index.map do |value, column_index|
        cell_xml(value, "#{column_name(column_index)}#{row_number}", style)
      end
      %(<row r="#{row_number}">#{cells.join}</row>)
    end

    # 빈 칸은 셀 자체를 만들지 않는다(엑셀이 빈 셀로 읽는다).
    # 숫자만 <v> 로 넣고 나머지는 전부 문자열 셀이라, 사용자 입력이 수식이 될 길이 없다.
    def cell_xml(value, reference, style)
      return "" if value.nil? || value.to_s.empty?

      attributes = %(r="#{reference}")
      attributes += %( s="#{style}") if style.positive?

      if value.is_a?(Numeric)
        %(<c #{attributes}><v>#{number_literal(value)}</v></c>)
      else
        %(<c #{attributes} t="inlineStr"><is><t xml:space="preserve">#{escape(value.to_s)}</t></is></c>)
      end
    end

    def number_literal(value)
      case value
      when BigDecimal then value.to_s("F")
      when Rational then value.to_f.to_s
      else value.to_s
      end
    end

    def column_name(index)
      name = +""
      number = index + 1
      while number.positive?
        number, remainder = (number - 1).divmod(26)
        name.prepend((65 + remainder).chr)
      end
      name
    end

    def escape(text)
      text.to_s
          .gsub(INVALID_XML_CHARS, "")
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
    end
  end
end
