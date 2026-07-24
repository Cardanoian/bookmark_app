require "cgi"
require "tempfile"
require "zip"

# 추천도서 업로드 테스트가 바이너리 fixture 에 의존하지 않도록 최소 XLSX 워크북을 만든다.
module XlsxTestHelper
  HEADERS = [ "번호", "호수", "분과명", "책제목", "저자", "출판사", "가격", "출간일", "ISBN" ].freeze

  def build_recommendation_xlsx(rows)
    table = [
      [ "테스트 추천도서목록" ],
      HEADERS,
      *rows.each_with_index.map do |row, index|
        [ index + 1, row.fetch(:issue, "2월호"), row.fetch(:section), row.fetch(:title),
          row[:author], row[:publisher], "15,000원", row.fetch(:published_on, "2026.02.01"), row[:isbn] ]
      end
    ]
    strings = table.flatten.map(&:to_s)
    string_index = 0
    sheet_rows = table.each_with_index.map do |values, row_index|
      cells = values.each_with_index.map do |_value, column_index|
        reference = "#{column_name(column_index)}#{row_index + 1}"
        cell = %(<c r="#{reference}" t="s"><v>#{string_index}</v></c>)
        string_index += 1
        cell
      end.join
      %(<row r="#{row_index + 1}">#{cells}</row>)
    end.join

    tempfile = Tempfile.new([ "recommendations", ".xlsx" ])
    tempfile.binmode
    Zip::OutputStream.open(tempfile.path) do |zip|
      write_zip_entry(zip, "xl/workbook.xml", workbook_xml)
      write_zip_entry(zip, "xl/_rels/workbook.xml.rels", workbook_relationships_xml)
      write_zip_entry(zip, "xl/sharedStrings.xml", shared_strings_xml(strings))
      write_zip_entry(zip, "xl/worksheets/sheet1.xml", worksheet_xml(sheet_rows))
    end
    tempfile
  end

  private

  def column_name(index)
    name = +""
    number = index + 1
    while number.positive?
      number, remainder = (number - 1).divmod(26)
      name.prepend((65 + remainder).chr)
    end
    name
  end

  def write_zip_entry(zip, name, contents)
    zip.put_next_entry(name)
    zip.write(contents)
  end

  def workbook_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="전체목록(이름순)" sheetId="1" r:id="rId1"/></sheets>
      </workbook>
    XML
  end

  def workbook_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
                      Target="worksheets/sheet1.xml"/>
      </Relationships>
    XML
  end

  def shared_strings_xml(strings)
    items = strings.map { |value| "<si><t>#{CGI.escapeHTML(value)}</t></si>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">#{items}</sst>)
  end

  def worksheet_xml(rows)
    %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{rows}</sheetData></worksheet>)
  end
end
