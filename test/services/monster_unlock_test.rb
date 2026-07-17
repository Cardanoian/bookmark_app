require "test_helper"

# 몬스터 자동 해금 평가 서비스(monster_unlocks.md §4). 미보유·stage1·unlock_condition 라인만
# 순회해 ReadingStats#meets? 충족 시 지급하고, dex_count 캐스케이드는 내부 fixpoint 루프로 처리한다.
class MonsterUnlockTest < ActiveSupport::TestCase
  setup do
    seed_monster_species!
    @school = School.create!(name: "해금초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "해금학생", password: "password")
  end

  def report(attrs = {})
    Report.create!({ user: @user, classroom: @classroom, book_title: "책" }.merge(attrs))
  end

  def owned_dex
    @user.user_monsters.pluck(:dex_no).sort
  end

  test "discovers the fastest common line (dex 09, reports:1) after one approved report" do
    report(reviewed: true)
    discovered = MonsterUnlock.new(@user).evaluate!
    assert_includes discovered.map(&:dex_no), 9
    assert_includes owned_dex, 9
  end

  test "does not discover a line whose condition is not yet met" do
    # dex 04 = reports:8 AND distinct_genres:3 — 승인 3편·장르 1종이면 미충족.
    3.times { report(reviewed: true, book: Book.create!(title: "추천책#{SecureRandom.hex(2)}", category: :recommended)) }
    MonsterUnlock.new(@user).evaluate!
    assert_not_includes owned_dex, 4
  end

  test "AND multi-condition line unlocks only when all clauses are met" do
    # dex 04 = reports:8 AND distinct_genres:3.
    8.times { report(reviewed: true, book: Book.create!(title: "장르책#{SecureRandom.hex(2)}", category: :recommended)) }
    MonsterUnlock.new(@user).evaluate!
    assert_not_includes owned_dex, 4, "장르 1종이면 아직 미충족"

    # 고전·검색 카테고리 책을 더해 장르 3종 확보.
    report(reviewed: true, book: Book.create!(title: "고전책", category: :classic))
    report(reviewed: true, book: Book.create!(title: "검색책", category: :searched))
    MonsterUnlock.new(@user).evaluate!
    assert_includes owned_dex, 4, "reports:8 AND distinct_genres:3 모두 충족 시 해금"
  end

  test "re-running evaluate! is idempotent and never double-grants a line" do
    report(reviewed: true)
    MonsterUnlock.new(@user).evaluate!
    assert_equal [], MonsterUnlock.new(@user).evaluate!.map(&:dex_no)
    assert_equal 1, @user.user_monsters.where(dex_no: 9).count
  end

  test "an unselected starter line is unlockable through its activity clause" do
    # dex 01(갈피멍) 스타터를 고르지 않아도 승인 독후감 3편이면 활동절(reports:3)로 해금된다.
    3.times { report(reviewed: true) }
    MonsterUnlock.new(@user).evaluate!
    assert_includes owned_dex, 1
  end

  test "already-owned lines are skipped (starter chosen then re-evaluated)" do
    MonsterAcquisition.new(@user).choose_starter!("cat_1") # dex 05
    # dex 05 unlock = distinct_genres:2. 조건을 채워도 이미 보유라 중복 지급 없음.
    report(reviewed: true, book: Book.create!(title: "장르A", category: :recommended))
    report(reviewed: true, book: Book.create!(title: "장르B", category: :classic))
    MonsterUnlock.new(@user).evaluate!
    assert_equal 1, @user.user_monsters.where(dex_no: 5).count
  end

  test "a line's discovery error is rescued and does not abort the evaluation" do
    report(reviewed: true) # dex 09 해금 조건 충족
    boom = Object.new
    def boom.discover_monster!(_identifier)
      raise StandardError, "일시적 실패"
    end
    # 내부 acquisition 을 항상 예외를 던지는 더블로 주입해 rescue 경로(nil 반환·계속 진행)를 검증한다.
    unlock = MonsterUnlock.new(@user)
    unlock.instance_variable_set(:@acquisition, boom)
    assert_nothing_raised do
      assert_equal [], unlock.evaluate!
    end
  end

  # fixpoint 캐스케이드 — dex 24 는 dex_count:20 조건이 있어, 20번째 라인을 만든 그 evaluate! 호출이
  # 서비스 내부 루프로 dex 24 까지 같은 호출에서 해금해야 한다(monster_unlocks.md §3B).
  test "dex_count cascade: the call that reaches 20 lines also unlocks dex 24 in the same evaluate!" do
    # 1) dex 1..19 를 직접 보유(19라인). dex_count = 19.
    (1..19).each do |dex_no|
      species = MonsterSpecies.find_by(dex_no: dex_no, stage: 1)
      @user.user_monsters.create!(monster_species: species, dex_no: dex_no, obtained_at: Time.current)
    end
    assert_equal 19, @user.user_monsters.distinct.count(:dex_no)

    # 2) dex 24 의 비-dex_count 조건 충족: reports:20, a_grades:5, game_books:12.
    #    책 없는(book_title) 독후감으로 distinct_genres 를 0 으로 유지해 dex 22 등 오분해금을 피한다.
    base = Date.new(2026, 6, 1)
    20.times do |i|
      # 첫 7편은 연속 7일(streak_days:7 → 20번째로 열릴 dex 20 조건 revisions 와 함께).
      day = base + (i < 7 ? i : 0)
      level = i < 5 ? "A" : "B"      # a_grades:5
      improvement = i < 2 ? 1.5 : 0  # revisions:2 (dex 20 조건)
      report(reviewed: true, book: nil, created_at: day.to_time, level: level, improvement: improvement)
    end
    # game_books:12 = 서로 다른 책 12권을 quiz 로 플레이(distinct_games=1 로 유지해 dex 21/23 오분해금 방지).
    12.times do |i|
      @user.game_plays.create!(game_type: :quiz, book: Book.create!(title: "게임책#{i}", category: :recommended),
                               played_on: base + i)
    end

    stats = ReadingStats.new(@user)
    assert_equal 20, stats.reports
    assert_equal 5, stats.a_grades
    assert_equal 12, stats.game_books
    assert_equal 7, stats.streak_days
    assert_equal 2, stats.revisions
    assert_equal 1, stats.distinct_games

    # 3) 단일 evaluate! — 20번째 라인(dex 20)을 만든 뒤 같은 호출에서 dex 24 까지 캐스케이드로 해금.
    discovered = MonsterUnlock.new(@user).evaluate!
    dex_nos = discovered.map(&:dex_no)
    assert_includes dex_nos, 20, "20번째 라인(dex 20)이 이번 호출에서 열려야 한다"
    assert_includes dex_nos, 24, "dex_count 20 도달 후 같은 evaluate! 호출에서 dex 24 가 열려야 한다(fixpoint)"
    assert_includes owned_dex, 24
  end
end
