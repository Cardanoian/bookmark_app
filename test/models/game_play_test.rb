require "test_helper"

# 게임 완료 활동 원장(Phase 3B). 부분 유니크 인덱스 2개로 book 있는/없는 플레이를 각각 일일 dedup 한다.
class GamePlayTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "원장초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "원장학생", password: "password")
    @book = Book.create!(title: "원장책", category: :recommended)
    @today = Date.new(2026, 6, 1)
  end

  def play(game_type: :quiz, book: @book, played_on: @today)
    @user.game_plays.create!(game_type: game_type, book: book, played_on: played_on)
  end

  test "game_type enum defines the five catalog games" do
    assert_equal({ "quiz" => 0, "classic" => 1, "vocab" => 2, "whoami" => 3, "book" => 4 }, GamePlay.game_types)
  end

  # 책 있는 플레이: (user, game_type, book, 일자) 당 1회.
  test "same user, game, book and day is deduped (with-book partial unique index)" do
    play
    assert_raises(ActiveRecord::RecordNotUnique) { play }
  end

  # 책 없는 플레이: NULL 안전 dedup — (user, game_type, 일자) 당 1회(book_id 를 키에서 뺐다).
  test "same user, game and day with no book is deduped (null-safe partial unique index)" do
    play(book: nil)
    assert_raises(ActiveRecord::RecordNotUnique) { play(book: nil) }
  end

  test "different game_type on the same book and day is allowed" do
    play(game_type: :quiz)
    assert_nothing_raised { play(game_type: :vocab) }
  end

  test "different book on the same game and day is allowed" do
    play(book: @book)
    other = Book.create!(title: "다른책", category: :classic)
    assert_nothing_raised { play(book: other) }
  end

  test "same game and book on a different day is allowed" do
    play(played_on: @today)
    assert_nothing_raised { play(played_on: @today + 1) }
  end

  # 두 부분 인덱스가 모두 존재하고 유니크·부분 술어를 갖는지 확인(스키마 회귀 방지).
  test "both daily-dedup partial unique indexes exist with the expected predicates" do
    indexes = ActiveRecord::Base.connection.indexes("game_plays")
    with_book = indexes.find { |i| i.name == "index_game_plays_daily_dedup_with_book" }
    without_book = indexes.find { |i| i.name == "index_game_plays_daily_dedup_without_book" }

    assert_not_nil with_book
    assert with_book.unique
    assert_equal "book_id IS NOT NULL", with_book.where

    assert_not_nil without_book
    assert without_book.unique
    assert_equal "book_id IS NULL", without_book.where
  end
end
