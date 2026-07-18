require "zip"
require "nokogiri"
require "pathname"

module Recommendations
  # 추천도서 업로드 양식의 첫 "전체목록" 시트를 읽는 작은 XLSX 리더다. 매크로나 수식은
  # 실행하지 않고 ZIP 안의 workbook/sharedStrings/worksheet XML 값만 읽는다.
  class XlsxReader
    class Error < StandardError; end

    Entry = Struct.new(:issue, :section, :title, :author, :publisher, :published_on, :isbn,
                       keyword_init: true)

    MAX_FILE_SIZE = 10.megabytes
    MAX_XML_SIZE = 20.megabytes
    MAX_ROWS = 5_000
    ELEMENTARY_SECTION = /\A어린이/

    HEADER_NAMES = {
      issue: %w[호수 추천호],
      section: %w[분과명 분과 구분],
      title: %w[책제목 도서명 제목],
      author: %w[저자 지은이],
      publisher: %w[출판사],
      published_on: %w[출간일 발행일],
      isbn: %w[ISBN ISBN13]
    }.freeze
    REQUIRED_HEADERS = %i[section title author publisher isbn].freeze

    attr_reader :source_title

    def initialize(path)
      @path = path.to_s
    end

    def read
      validate_file!

      rows = Zip::File.open(@path) do |zip|
        strings = shared_strings(zip)
        worksheet_rows(zip, primary_worksheet_path(zip), strings)
      end
      parse_entries(rows)
    rescue Zip::Error, Nokogiri::XML::SyntaxError => error
      raise Error, "올바른 XLSX 파일이 아닙니다: #{error.message}"
    end

    private

    def validate_file!
      raise Error, "업로드한 파일을 읽을 수 없습니다." unless File.file?(@path)
      raise Error, "XLSX 파일은 10MB 이하만 업로드할 수 있습니다." if File.size(@path) > MAX_FILE_SIZE
    end

    def xml(zip, entry_name)
      entry = zip.find_entry(entry_name)
      raise Error, "XLSX 구성 파일이 없습니다: #{entry_name}" unless entry
      raise Error, "XLSX 내부 XML이 너무 큽니다." if entry.size > MAX_XML_SIZE

      Nokogiri::XML(entry.get_input_stream.read) { |config| config.strict.nonet }.tap(&:remove_namespaces!)
    end

    def shared_strings(zip)
      return [] unless zip.find_entry("xl/sharedStrings.xml")

      xml(zip, "xl/sharedStrings.xml").xpath("//si").map do |node|
        node.xpath(".//t").map(&:text).join
      end
    end

    def primary_worksheet_path(zip)
      workbook = xml(zip, "xl/workbook.xml")
      sheet = workbook.xpath("//sheet").find { |node| node["name"].to_s.start_with?("전체목록") }
      sheet ||= workbook.at_xpath("//sheet")
      raise Error, "워크북에 시트가 없습니다." unless sheet

      relation_id = sheet["id"]
      relationships = xml(zip, "xl/_rels/workbook.xml.rels")
      relationship = relationships.xpath("//Relationship").find { |node| node["Id"] == relation_id }
      raise Error, "전체목록 시트 연결을 찾을 수 없습니다." unless relationship

      target = relationship["Target"].to_s.sub(%r{\A/}, "")
      target = "xl/#{target}" unless target.start_with?("xl/")
      clean_target = Pathname.new(target).cleanpath.to_s
      unless clean_target.match?(%r{\Axl/worksheets/[^/]+\.xml\z})
        raise Error, "안전하지 않은 워크시트 경로입니다."
      end

      clean_target
    end

    def worksheet_rows(zip, sheet_path, strings)
      document = xml(zip, sheet_path)
      nodes = document.xpath("//sheetData/row")
      raise Error, "추천도서 행이 너무 많습니다." if nodes.size > MAX_ROWS

      nodes.map do |row|
        row.xpath("./c").to_h do |cell|
          [ column_index(cell["r"]), cell_value(cell, strings) ]
        end
      end
    end

    def column_index(reference)
      reference.to_s[/\A[A-Z]+/].to_s.each_byte.reduce(0) { |number, byte| number * 26 + byte - 64 } - 1
    end

    def cell_value(cell, strings)
      case cell["t"]
      when "s"
        strings.fetch(cell.at_xpath("./v")&.text.to_i, "")
      when "inlineStr"
        cell.xpath(".//t").map(&:text).join
      else
        cell.at_xpath("./v")&.text.to_s
      end.to_s.strip
    end

    def parse_entries(rows)
      header_row_index, columns = find_header(rows)
      @source_title = rows.first(header_row_index).filter_map { |row| row.values.find(&:present?) }.first

      entries = rows.drop(header_row_index + 1).filter_map.with_index(header_row_index + 2) do |row, row_number|
        values = columns.transform_values { |column| row[column].to_s.strip }
        next if values[:title].blank? && values[:isbn].blank?
        next unless values[:section].match?(ELEMENTARY_SECTION)

        isbn = values[:isbn].gsub(/\D/, "")
        if isbn.present? && ![ 10, 13 ].include?(isbn.length)
          raise Error, "#{row_number}행 ISBN 형식이 올바르지 않습니다."
        end
        raise Error, "#{row_number}행 책 제목이 비어 있습니다." if values[:title].blank?

        Entry.new(
          issue: values[:issue].presence,
          section: values[:section],
          title: values[:title],
          author: values[:author].presence,
          publisher: values[:publisher].presence,
          published_on: parse_date(values[:published_on], row_number),
          isbn: isbn.presence
        )
      end

      raise Error, "어린이 분과 추천도서가 한 권도 없습니다." if entries.empty?

      entries
    end

    def find_header(rows)
      rows.first(20).each_with_index do |row, index|
        normalized = row.transform_values { |value| normalize_header(value) }
        columns = HEADER_NAMES.to_h do |key, names|
          column = normalized.key(names.map { |name| normalize_header(name) }.find { |name| normalized.value?(name) })
          [ key, column ]
        end
        return [ index, columns ] if REQUIRED_HEADERS.all? { |key| columns[key] }
      end

      raise Error, "필수 열(분과명, 책제목, 저자, 출판사, ISBN)을 찾을 수 없습니다."
    end

    def normalize_header(value)
      value.to_s.upcase.gsub(/[\s_-]/, "")
    end

    def parse_date(value, row_number)
      return if value.blank?

      if value.match?(/\A\d{5}(?:\.\d+)?\z/)
        return Date.new(1899, 12, 30) + value.to_f.to_i
      end

      Date.parse(value.tr(".", "-"))
    rescue Date::Error
      raise Error, "#{row_number}행 출간일 형식이 올바르지 않습니다."
    end
  end
end
