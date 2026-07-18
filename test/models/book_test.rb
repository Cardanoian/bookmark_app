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

  test "isbn is not required (searched books cache without one)" do
    assert Book.new(title: "검색된 책", category: :searched, isbn: nil).valid?
  end

  # isbn 유일성 — 소프트 게이트(검증)와 하드 백스톱(부분 유니크 인덱스 index_books_on_isbn,
  # 마이그레이션 20260718000004)의 2중 방어.
  test "uniqueness validation rejects a duplicate non-blank isbn gracefully (soft gate)" do
    Book.create!(title: "첫 책", isbn: "9791111111111", category: :searched)
    dup = Book.new(title: "중복 책", isbn: "9791111111111", category: :searched)
    assert_not dup.valid?, "중복 isbn 은 검증에서 걸러진다(폼 에러로 강등)"
    assert_includes dup.errors.attribute_names, :isbn
  end

  test "partial unique index still backstops a duplicate isbn when validation is bypassed (hard backstop)" do
    Book.create!(title: "첫 책", isbn: "9791111111111", category: :searched)
    dup = Book.new(title: "중복 책", isbn: "9791111111111", category: :searched)
    assert_raises(ActiveRecord::RecordNotUnique) do
      dup.save(validate: false) # 검증 우회 시에도 DB 인덱스가 동시성 중복을 차단
    end
  end

  test "partial unique index allows multiple null-isbn rows (text-only titles are outside the predicate)" do
    Book.create!(title: "제목만 A", isbn: nil, category: :searched)
    Book.create!(title: "제목만 B", isbn: nil, category: :searched)
    assert_equal 2, Book.where(isbn: nil).where("title LIKE ?", "제목만%").count
  end

  test "partial unique index allows multiple empty-string isbn rows (excluded by isbn != '')" do
    Book.create!(title: "빈 isbn A", isbn: "", category: :searched)
    Book.create!(title: "빈 isbn B", isbn: "", category: :searched)
    assert_equal 2, Book.where(isbn: "").where("title LIKE ?", "빈 isbn%").count
  end
end
