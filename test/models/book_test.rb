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
end
