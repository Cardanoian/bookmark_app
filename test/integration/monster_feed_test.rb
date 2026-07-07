require "test_helper"

# P1.7 — 먹이주기(소모품 수량 -1 → 케어 갱신). 원자적 조건부 차감으로 동시 요청이
# 수량을 음수로 만들거나 이중 소비하지 않음을 검증한다(lost update 방지).
class MonsterFeedTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "먹이초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "먹이학생", password: "password")
    @monster = MonsterAcquisition.new(@student).choose_starter!("pup_1")
    @food = ShopItem.create!(name: "책갈피 간식", category: :food, cost: 20, consumable: true,
                             effect: { "evolve_boost" => true })
  end

  def buy!(item, quantity)
    @student.purchases.create!(shop_item: item, quantity: quantity, bought_at: Time.current)
  end

  test "feeding consumes one item and applies the care effect" do
    purchase = buy!(@food, 2)
    login_as @student

    post feed_monster_path(@monster.dex_no), params: { shop_item_id: @food.id }

    assert_redirected_to monster_path(@monster.dex_no)
    assert_equal 1, purchase.reload.quantity, "먹이 하나만 소비"
    care = @monster.reload.care
    assert_equal 1, care["fed_count"]
    assert_equal 1, care["evolve_boost"], "effect(evolve_boost) 가 케어에 반영"
  end

  test "feeding is refused (no consume, no care) when the item is not owned" do
    login_as @student

    post feed_monster_path(@monster.dex_no), params: { shop_item_id: @food.id }

    assert_redirected_to monster_path(@monster.dex_no)
    assert_equal 0, @student.purchases.count
    assert_nil @monster.reload.care
  end

  test "feeding is refused when the owned quantity is already zero" do
    buy!(@food, 0)
    login_as @student

    post feed_monster_path(@monster.dex_no), params: { shop_item_id: @food.id }

    assert_redirected_to monster_path(@monster.dex_no)
    assert_equal 0, @student.purchases.find_by(shop_item: @food).quantity, "수량 0 은 음수가 되지 않는다"
    assert_nil @monster.reload.care, "차감 실패 시 케어 효과도 없다"
  end

  # 잔여 수량 1 을 두 요청이 동시에 노리면, 컨트롤러의 원자적 조건부 차감으로 정확히 하나만
  # 성공하고 수량은 절대 음수가 되지 않는다(precheck→decrement 의 lost update 회귀 방지).
  # MonstersController#feed 가 실행하는 것과 동일한 원자 문(quantity>0 WHERE + update_all)을 검증한다.
  test "concurrent feed of a quantity-1 item consumes exactly once and never goes negative" do
    purchase = buy!(@food, 1)

    results = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          with_retry_on_lock do
            Purchase.where(id: purchase.id).where("quantity > 0").update_all("quantity = quantity - 1")
          end
        end
      end
    end.map(&:value)

    assert_equal 1, results.count { |affected| affected == 1 }, "수량 1 은 정확히 한 번만 소비돼야 한다"
    assert_equal 0, purchase.reload.quantity, "수량은 절대 음수가 되지 않는다"
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end

  # SQLite 는 동시 쓰기 경합 시 "database is locked" 를 던질 수 있다 — 잠깐 뒤 재시도(pointable_test 와 동일).
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
