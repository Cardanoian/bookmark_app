require "test_helper"
require Rails.root.join("db/seeds/demo_seeder").to_s

# 데모 시더의 게임 기록 계약(2026-09-19). 책 소개·뒷이야기 완료 기록은 같은 책의 글과 함께 만들고
# (글 없는 "완료"는 화면에서 볼 글이 없었다 — 운영 체험 이도현 『검피 아저씨의 뱃놀이』), 글의 날짜는
# 1학기(5/1~7/20)에 주로·9월에 조금·8월(방학)은 없다. 예시 글 풀이 없는 환경에서는 예전처럼 기록만 만든다.
class DemoData::DemoSeederGamesTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "시드게임초")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @teacher = User.create!(school: @school, name: "시드담임", role: :teacher, email: "seedgames_t@example.com", password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "시드학생", password: "password")
    @peer = User.create!(school: @school, classroom: @classroom, name: "시드친구", password: "password")
    @seeder = DemoSeeder.new(io: StringIO.new)
    # 시더의 기본 도서 풀(줄거리 있는 책 — 퀴즈 기록이 여기서 책을 고른다)과, 예시 글 풀(book_social.yml)에 있는
    # 책. 예시 글 책은 줄거리를 비워 기본 풀과 겹치지 않게 한다 — 겹치면 사용자 id 에 따라 퀴즈 기록이 예시 글
    # 책을 먼저 가져가 글 쓸 책이 모자라는 불안정한 테스트가 된다.
    8.times { |i| Book.create!(title: "풀 도서 #{i}", summary: "줄거리", category: :recommended) }
    social = YAML.load_file(DemoSeeder::SOCIAL_TEXTS_PATH)
    @social_books = social.first(10).map do |isbn, texts|
      Book.create!(title: texts.fetch("title"), isbn: isbn, category: :recommended)
    end
  end

  test "book and sequel plays are written on the same book and day, as approved entries" do
    st = seed_games_for(@student, plays: 8)

    plays = GamePlay.where(user: @student)
    assert_equal 8, plays.count
    assert_equal 80, st[:game_points]
    written = plays.where(game_type: %w[book sequel]).to_a
    assert_equal 4, written.size
    written.each do |play|
      entry = (play.book? ? BookIntro : BookSequel).find_by!(user: @student, book_id: play.book_id)
      assert_equal play.played_on, entry.created_at.to_date, "글 날짜 = 완료 기록 날짜"
      assert_includes @social_books.map(&:id), play.book_id, "예시 글이 있는 책"
    end
    sequels = BookSequel.where(user: @student)
    assert sequels.all?(&:comment_visible?), "시드 뒷이야기는 담임이 승인한 글이다"
    assert_equal [ @teacher.id ], sequels.map(&:reviewed_by_id).uniq

    quiz_books = plays.where(game_type: %w[quiz whoami]).pluck(:book_id)
    assert_empty quiz_books & written.map(&:book_id), "게임으로 만난 책 수가 줄지 않게 다른 책에 쓴다"
    assert_equal 8, plays.distinct.count(:book_id)

    # 서재의 뒷이야기·책 소개 필터에 그 책들이 오른다(쓴 글이 있어 완료로 보인다).
    assert_equal written.select(&:sequel?).map(&:book_id).sort, StudentLibraryQuery.new(@student, kind: "sequel").entries.map { |e| e.book.id }.sort
    assert_equal written.select(&:book?).map(&:book_id).sort, StudentLibraryQuery.new(@student, kind: "book").entries.map { |e| e.book.id }.sort
  end

  test "writing dates fall in the first term or September, never in August or the future" do
    seed_games_for(@student, plays: 8)
    dates = BookSequel.where(user: @student).map { |s| s.created_at.to_date } +
            BookIntro.where(user: @student).map { |s| s.created_at.to_date }

    dates.each do |date|
      assert date < Date.current, "#{date} 는 오늘 전이어야 한다"
      assert_not_equal 8, date.month, "#{date} — 8월(방학)은 없다"
      first_term = date >= Date.new(date.year, 5, 1) && date <= Date.new(date.year, 7, 20)
      assert first_term || date.month == 9, "#{date} 는 1학기(5/1~7/20)나 9월이어야 한다"
    end
  end

  test "classmates do not get the same example text for the same book" do
    seed_games_for(@student, plays: 8)
    seed_games_for(@peer, plays: 8)

    sequel_books = BookSequel.where(classroom: @classroom).pluck(:book_id)
    intro_books = BookIntro.where(classroom: @classroom).pluck(:book_id)
    assert_equal sequel_books.size, sequel_books.uniq.size
    assert_equal intro_books.size, intro_books.uniq.size
  end

  test "without example texts the plays are seeded as before, with no written entries" do
    Book.where(id: @social_books.map(&:id)).delete_all
    seed_games_for(@student, plays: 8)

    assert_equal 8, GamePlay.where(user: @student).count
    assert_not BookSequel.where(user: @student).exists?
    assert_not BookIntro.where(user: @student).exists?
  end

  private

  def seed_games_for(user, plays:)
    st = { user:, sd: { "game_plays" => plays }, classroom: @classroom, game_points: 0 }
    @seeder.send(:seed_games, st)
    st
  end
end
