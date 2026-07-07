require "test_helper"

class PointableTest < ActiveSupport::TestCase
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "포인트초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "포인트학생", password: "password")
  end

  test "award_points increments and persists points" do
    @user.award_points(30)
    assert_equal 30, @user.reload.points
    @user.award_points(20)
    assert_equal 50, @user.reload.points
  end

  test "award_points ignores zero and negative amounts" do
    @user.award_points(0)
    @user.award_points(-10)
    assert_equal 0, @user.reload.points
  end

  test "award_points triggers badge refresh" do
    3.times { Report.create!(user: @user, classroom: @classroom, book_title: "책", reviewed: true) }
    @user.award_points(30)
    keys = @user.badges.reload.pluck(:key)
    assert_includes keys, "first"
    assert_includes keys, "three"
  end

  test "award_points triggers evolution check without auto-evolving" do
    MonsterAcquisition.new(@user).choose_starter!("pup_1")
    3.times { Report.create!(user: @user, classroom: @classroom, book_title: "책", reviewed: true) }

    # 99 -> still below threshold, not evolvable
    @user.award_points(99)
    assert_not @user.check_evolution!

    # crossing 100 makes it evolvable, but award_points must not auto-evolve
    @user.award_points(1)
    assert @user.check_evolution!
    assert_equal "pup_1", @user.active_monster.reload.monster_species.key
  end

  # 두 스레드가 같은 유저에 동시에 적립해도 원자 증가(update_counters)라 합계가 정확해야 한다(lost update 없음).
  test "concurrent award_points do not lose updates" do
    @user.update!(points: 0)

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          with_retry_on_lock { User.find(@user.id).award_points(50) }
        end
      end
    end
    threads.each(&:join)

    assert_equal 100, @user.reload.points, "동시 적립이 lost update 없이 합산돼야 한다"
  end

  # 잔액이 한 번만 감당하는데 두 차감이 경쟁하면 정확히 하나만 성공하고 잔액은 절대 음수가 되지 않는다.
  test "concurrent spend_points! lets exactly one competing spend win (never negative)" do
    @user.update!(points: 50)

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          with_retry_on_lock { User.find(@user.id).spend_points!(50) }
        end
      end
    end
    results = threads.map(&:value)

    assert_equal 1, results.count(true), "잔액이 하나만 감당하면 정확히 한 번만 성공해야 한다"
    assert_equal 0, @user.reload.points, "잔액은 절대 음수가 되지 않는다"
  end

  test "spend_points! deducts atomically and returns true on sufficient balance" do
    @user.update!(points: 50)
    assert @user.spend_points!(30)
    assert_equal 20, @user.reload.points
  end

  test "spend_points! returns false and does not change points when balance is insufficient" do
    @user.update!(points: 10)
    assert_not @user.spend_points!(50)
    assert_equal 10, @user.reload.points
  end

  test "spend_points! ignores zero and negative amounts without changing points" do
    @user.update!(points: 50)
    assert_not @user.spend_points!(0)
    assert_not @user.spend_points!(-10)
    assert_equal 50, @user.reload.points
  end

  private

  # SQLite 는 동시 쓰기 경합 시 "database is locked" 를 던질 수 있다 — busy_timeout 이후에도 실패하면 잠깐 뒤 재시도.
  def with_retry_on_lock(attempts: 5)
    yield
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.message.match?(/database is locked|SQLITE_BUSY/i)

    attempts -= 1
    raise if attempts <= 0

    sleep(0.05)
    retry
  end
end
