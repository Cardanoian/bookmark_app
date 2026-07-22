require "test_helper"

class BookTest < ActiveSupport::TestCase
  test "category enum defines three values" do
    assert_equal(
      { "recommended" => 0, "classic" => 1, "searched" => 2 },
      Book.categories
    )
  end

  test "defaults to the recommended category" do
    assert Book.new.recommended?
  end

  test "requires a title" do
    assert_not Book.new(title: nil).valid?
    assert Book.new(title: "어린 왕자").valid?
  end

  test "requires isbn for every category" do
    %i[recommended classic searched].each do |category|
      book = Book.new(title: "ISBN 없는 책", category: category, isbn: nil)
      assert_not book.valid?
      assert_includes book.errors.attribute_names, :isbn
    end
  end

  test "normalizes hyphenated ISBN-13 and converts valid ISBN-10" do
    assert_equal "9788986621136", Books::Isbn.normalize("978-89-86621-13-6")
    assert_equal "9788986621136", Books::Isbn.normalize("8986621134")

    book = Book.create!(title: "하이픈 책", isbn: "978-89-86621-13-6")
    assert_equal "9788986621136", book.isbn
  end

  # isbn 유일성 — 소프트 게이트(검증)와 하드 백스톱(전체 유니크 인덱스)의 2중 방어.
  test "uniqueness validation rejects a duplicate non-blank isbn gracefully (soft gate)" do
    Book.create!(title: "첫 책", isbn: "9791111111112", category: :searched)
    dup = Book.new(title: "중복 책", isbn: "9791111111112", category: :searched)
    assert_not dup.valid?, "중복 isbn 은 검증에서 걸러진다(폼 에러로 강등)"
    assert_includes dup.errors.attribute_names, :isbn
  end

  test "unique index still backstops a duplicate isbn when validation is bypassed (hard backstop)" do
    Book.create!(title: "첫 책", isbn: "9791111111112", category: :searched)
    dup = Book.new(title: "중복 책", isbn: "9791111111112", category: :searched)
    assert_raises(ActiveRecord::RecordNotUnique) do
      dup.save(validate: false) # 검증 우회 시에도 DB 인덱스가 동시성 중복을 차단
    end
  end

  test "database rejects null isbn when validation is bypassed" do
    assert_raises(ActiveRecord::NotNullViolation) do
      Book.new(title: "제목만", isbn: nil).save!(validate: false)
    end
  end

  test "database format check rejects empty isbn when validation is bypassed" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Book.new(title: "빈 ISBN", isbn: "").save!(validate: false)
    end
  end

  # HTTPS 배포(force_ssl)에서 http:// 표지는 혼합 콘텐츠로 차단되므로 저장 전 https 로 승격한다.
  test "upgrades an http cover_url to https on save (mixed-content guard)" do
    book = Book.create!(title: "표지 책", isbn: "9791111111112",
                        cover_url: "http://image.aladin.co.kr/x.jpg")
    assert_equal "https://image.aladin.co.kr/x.jpg", book.cover_url
  end

  test "leaves an https cover_url and blank cover_url untouched" do
    https = Book.create!(title: "https 책", isbn: "9791111111112",
                         cover_url: "https://image.aladin.co.kr/y.jpg")
    assert_equal "https://image.aladin.co.kr/y.jpg", https.cover_url

    blank = Book.create!(title: "표지 없는 책", isbn: "9788986621136", cover_url: nil)
    assert_nil blank.cover_url
  end

  # 검색 캐시(searched) 도서가 승인 독후감으로 실제 읽혔음이 확인되면 정식 카탈로그로 승격된다
  # (독서활동 허브·자동완성·발견 정상화 — 막다른 길 해소).
  test "promote_from_search! promotes a searched book to the recommended catalog" do
    book = Book.create!(title: "검색으로 찾은 무명책", isbn: "9791112114198", category: :searched)
    book.promote_from_search!
    assert book.reload.recommended?
  end

  test "promote_from_search! is a no-op for non-searched books (idempotent)" do
    classic = Book.create!(title: "고전", isbn: "9791112114198", category: :classic)
    classic.promote_from_search!
    assert classic.reload.classic?, "고전은 승격 대상이 아니다(불변)"

    recommended = Book.create!(title: "이미 추천", isbn: "9788986621136", category: :recommended)
    recommended.promote_from_search!
    assert recommended.reload.recommended?
  end
end
