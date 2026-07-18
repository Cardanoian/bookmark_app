require "test_helper"
require "rake"
require "tempfile"
require "csv"

# books:seed_full 검증(Task2 계획). 소형 fixture TSV 로 파서의 공란 정규화·category/grade_band
# 매핑(화이트리스트 폴백 포함)·isbn 멱등·다권 보존·summary 비파괴·searched 캐시 비충돌을 검증한다
# (8,502행 전량을 테스트 DB 에 넣지 않는다. schools_seed_test.rb 의 Tempfile 패턴을 따른다).
class BooksSeedFullTest < ActiveSupport::TestCase
  HEADERS = %w[title author publisher isbn13 project_category cover_url primary_grade_band].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("books:seed_full")
    @tsv = write_tsv([
      { title: "테스트책1", author: "홍길동", publisher: "테스트출판사", isbn13: "9791100000001",
        project_category: "recommended", cover_url: "https://example.com/1.jpg", primary_grade_band: "초등 1~2" },
      { title: "테스트책2", author: "김철수", publisher: "", isbn13: "",
        project_category: "classic", cover_url: "", primary_grade_band: "" },
      { title: "테스트책3", author: "이영희", publisher: "미분류출판", isbn13: "9791100000003",
        project_category: "unknown_category", cover_url: "", primary_grade_band: "검토필요" }
    ])
  end

  teardown do
    @tsv&.close!
  end

  def write_tsv(rows)
    file = Tempfile.new([ "elementary_books", ".tsv" ])
    CSV.open(file.path, "w", col_sep: "\t") do |csv|
      csv << HEADERS
      rows.each { |row| csv << HEADERS.map { |header| row[header.to_sym] } }
    end
    file
  end

  def seed_full!(path = @tsv.path)
    ENV["BOOKS_TSV"] = path
    Rake::Task["books:seed_full"].reenable
    capture_io { Rake::Task["books:seed_full"].invoke }
  ensure
    ENV.delete("BOOKS_TSV")
  end

  test "공란 컬럼은 nil 로 정규화되고 title 만 있으면 적재된다" do
    seed_full!

    book = Book.find_by(title: "테스트책2")
    assert_not_nil book
    assert_nil book.publisher
    assert_nil book.isbn
    assert_nil book.cover_url
    assert_nil book.grade_band
  end

  test "project_category 를 recommended/classic 으로 매핑하고 미지 값은 recommended 로 폴백한다" do
    seed_full!

    assert_equal "recommended", Book.find_by(title: "테스트책1").category
    assert_equal "classic", Book.find_by(title: "테스트책2").category
    assert_equal "recommended", Book.find_by(title: "테스트책3").category, "미지 project_category 는 recommended 폴백"
  end

  test "primary_grade_band 는 Book::GRADE_BANDS 화이트리스트 안에서만 대입되고 밖은 nil 로 폴백한다" do
    seed_full!

    assert_equal "초등 1~2", Book.find_by(title: "테스트책1").grade_band
    assert_nil Book.find_by(title: "테스트책3").grade_band, "화이트리스트 밖 라벨(검토필요)은 nil"
  end

  test "isbn 이 있으면 재실행해도 count 가 늘지 않는다(멱등)" do
    seed_full!
    count = Book.count
    seed_full!

    assert_equal count, Book.count
  end

  test "같은 title 이라도 isbn 이 다르면 별개 도서로 각각 보존된다" do
    tsv = write_tsv([
      { title: "같은제목", author: "작가A", publisher: "", isbn13: "9791100000011",
        project_category: "recommended", cover_url: "", primary_grade_band: "" },
      { title: "같은제목", author: "작가A", publisher: "", isbn13: "9791100000012",
        project_category: "recommended", cover_url: "", primary_grade_band: "" }
    ])

    seed_full!(tsv.path)

    assert_equal 2, Book.where(title: "같은제목").count
  ensure
    tsv&.close!
  end

  test "기존 큐레이션 summary 는 건드리지 않는다" do
    Book.create!(title: "테스트책1", author: "홍길동", isbn: "9791100000001",
                 summary: "손수 쓴 요약", category: :recommended)

    seed_full!

    assert_equal "손수 쓴 요약", Book.find_by(isbn: "9791100000001").summary
  end

  test "searched 캐시 행과 isbn 이 겹쳐도 캐시 행을 덮어쓰지 않는다" do
    searched = Book.create!(title: "검색캐시책", isbn: "9791100000001", category: :searched)

    seed_full!
    searched.reload

    assert_equal "검색캐시책", searched.title, "searched 행은 seed_full 이 건드리지 않는다"
    assert_equal "recommended", Book.find_by(title: "테스트책1").category,
                 "동일 isbn 이라도 카탈로그 신규 행이 별도로 생성된다(searched 캐시와 충돌하지 않음)"
  end

  test "파일이 없으면 안내 후 no-op(크래시 없음)" do
    assert_nothing_raised do
      out, = seed_full!("/tmp/does-not-exist-#{SecureRandom.hex(4)}.tsv")
      assert_match(/not found/, out)
    end
    assert_equal 0, Book.count
  end

  test "genre 열이 있으면 Book.genre 로 적재하고 미분류/공란은 무장르로 남긴다" do
    headers = HEADERS + %w[genre]
    file = Tempfile.new([ "books_genre", ".tsv" ])
    CSV.open(file.path, "w", col_sep: "\t") do |csv|
      csv << headers
      csv << [ "장르있는책", "작가", "", "9791100000021", "recommended", "", "", "문학" ]
      csv << [ "미분류책", "작가", "", "9791100000022", "recommended", "", "", "미분류" ]
      csv << [ "공란장르책", "작가", "", "9791100000023", "recommended", "", "", "" ]
    end

    seed_full!(file.path)

    assert_equal "문학", Book.find_by(title: "장르있는책").genre
    assert_nil Book.find_by(title: "미분류책").genre, "미분류는 무장르로 남겨 나중에 보강한다"
    assert_nil Book.find_by(title: "공란장르책").genre
  ensure
    file&.close!
  end
end
