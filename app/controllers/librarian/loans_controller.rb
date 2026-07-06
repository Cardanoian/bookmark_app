# 인기대출 관리(P6.5). 목록(Top) · 수동 입력 · 정보나루 동기화 · CSV 업로드.
# 정보나루 집계는 전국(NULL) 스코프, CSV·수동 입력은 자기 학교 스코프로 upsert 한다.
# CSV 는 외부 gem 없이 RFC 4180 규칙으로 직접 파싱한다(Ruby 4.0 은 csv stdlib 미번들).
class Librarian::LoansController < Librarian::BaseController
  # 헤더명 → 내부 키 매핑(한/영 허용). 미매핑 컬럼은 무시.
  HEADER_MAP = {
    "book_title" => :book_title, "title" => :book_title, "도서명" => :book_title, "제목" => :book_title,
    "isbn" => :isbn,
    "count" => :count, "loan_count" => :count, "대출건수" => :count, "대출횟수" => :count,
    "period" => :period, "기간" => :period
  }.freeze

  def index
    @loans = load_loans
    @loan = LibraryLoan.new
  end

  def create
    @loan = LibraryLoan.new(loan_params.merge(school: current_school, source: :csv))

    if @loan.save
      redirect_to librarian_loans_path, notice: "‘#{@loan.book_title}’ 대출 기록을 추가했어요."
    else
      @loans = load_loans
      render :index, status: :unprocessable_entity
    end
  end

  # 정보나루 인기대출 동기화(전국 NULL 스코프). 키 없음 → graceful CSV 폴백 안내.
  def sync_data4library
    service = Library::Data4libraryService.new

    unless service.available?
      redirect_to librarian_loans_path, notice: "정보나루 API 키가 없어요 — CSV 업로드를 사용하세요."
      return
    end

    period = Date.current.strftime("%Y-%m")
    loans = service.popular_loans
    loans.each { |attrs| upsert_loan(attrs.merge(source: :data4library, period: period), school_id: nil) }

    redirect_to librarian_loans_path, notice: "정보나루 인기대출 #{loans.size}건을 동기화했어요."
  end

  # 교육청 DLS CSV 업로드(자기 학교 스코프). 수동 RFC 4180 파싱 후 upsert.
  def import_csv
    file = params[:file]

    unless file.respond_to?(:read)
      redirect_to librarian_loans_path, alert: "CSV 파일을 선택해 주세요."
      return
    end

    imported = import_rows(parse_csv(file.read))
    redirect_to librarian_loans_path, notice: "CSV에서 #{imported}건을 반영했어요."
  end

  private

  # 자기 학교 + 전국(NULL) 인기대출. 대출건수 내림차순.
  def load_loans
    LibraryLoan.where(school_id: [ current_school&.id, nil ].uniq).order(count: :desc)
  end

  def import_rows(rows)
    return 0 if rows.size < 2

    keys = rows.first.map { |cell| HEADER_MAP[cell.to_s.strip.downcase] }
    period_default = Date.current.strftime("%Y-%m")

    rows.drop(1).count do |cells|
      attrs = row_attributes(keys, cells)
      next false if attrs[:book_title].blank?

      upsert_loan(attrs.merge(source: :csv, period: attrs[:period].presence || period_default),
                  school_id: current_school&.id)
    end
  end

  def row_attributes(keys, cells)
    attrs = {}
    keys.each_with_index { |key, index| attrs[key] = cells[index] if key }
    attrs
  end

  # [school_id, book_title, period] 로 upsert — 중복 업로드는 갱신만(멱등).
  def upsert_loan(attrs, school_id:)
    loan = LibraryLoan.find_or_initialize_by(
      school_id: school_id, book_title: attrs[:book_title].to_s.strip, period: attrs[:period]
    )
    loan.isbn = attrs[:isbn].to_s.strip if attrs[:isbn].present?
    loan.count = attrs[:count].to_i
    loan.source = attrs[:source]
    loan.save
  end

  def loan_params
    params.require(:library_loan).permit(:book_title, :isbn, :count, :period)
  end

  # RFC 4180 CSV 파서(외부 gem 없음). 따옴표·이스케이프(""), 인용 필드 내 개행·콤마 지원.
  # 반환: 행 배열(각 행은 셀 문자열 배열). BOM 제거.
  def parse_csv(text)
    # 업로드 본문은 ASCII-8BIT 로 들어올 수 있어 UTF-8 로 강제 후 BOM 제거한다.
    text = text.to_s.dup.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
    rows = []
    row = []
    field = +""
    in_quotes = false
    index = 0

    while index < text.length
      char = text[index]

      if in_quotes
        if char == '"'
          if text[index + 1] == '"'
            field << '"'
            index += 1
          else
            in_quotes = false
          end
        else
          field << char
        end
      elsif char == '"'
        in_quotes = true
      elsif char == ","
        row << field
        field = +""
      elsif char == "\n"
        row << field
        rows << row
        row = []
        field = +""
      elsif char == "\r"
        unless text[index + 1] == "\n"
          row << field
          rows << row
          row = []
          field = +""
        end
      else
        field << char
      end

      index += 1
    end

    row << field
    rows << row
    rows.reject { |cells| cells.all? { |cell| cell.to_s.strip.empty? } }
  end
end
