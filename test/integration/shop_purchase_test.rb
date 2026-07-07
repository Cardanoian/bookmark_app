require "test_helper"

# P4.8 — 상점 구매(포인트 sink). 차감·소모품 수량 누적·영구 아이템 유일성·잔액 부족 거부.
class ShopPurchaseTest < ActionDispatch::IntegrationTest
  setup do
    seed_badges!
    @school = School.create!(name: "상점초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "상점학생", password: "password")
    @food = ShopItem.create!(name: "책갈피 간식", category: :food, cost: 20, consumable: true, effect: {})
    @deco = ShopItem.create!(name: "책장 배경", category: :decoration, cost: 50, consumable: false, effect: {})
  end

  test "purchasing a consumable deducts points and stacks quantity" do
    @student.update!(points: 100)
    login_as @student

    post purchases_path, params: { shop_item_id: @food.id }
    assert_equal 80, @student.reload.points
    purchase = @student.purchases.find_by(shop_item: @food)
    assert_equal 1, purchase.quantity

    post purchases_path, params: { shop_item_id: @food.id }
    assert_equal 60, @student.reload.points
    assert_equal 2, purchase.reload.quantity
    assert_equal 1, @student.purchases.where(shop_item: @food).count, "소모품은 한 행에 수량 누적"
  end

  test "purchasing a permanent item is unique and rejects duplicates" do
    @student.update!(points: 200)
    login_as @student

    post purchases_path, params: { shop_item_id: @deco.id }
    assert_equal 150, @student.reload.points
    assert_equal 1, @student.purchases.where(shop_item: @deco).count

    post purchases_path, params: { shop_item_id: @deco.id }
    assert_equal 150, @student.reload.points, "중복 구매 시 추가 차감 없음"
    assert_equal 1, @student.purchases.where(shop_item: @deco).count
  end

  test "purchase is refused when points are insufficient" do
    @student.update!(points: 10)
    login_as @student

    post purchases_path, params: { shop_item_id: @food.id }

    assert_equal 10, @student.reload.points
    assert_equal 0, @student.purchases.count
  end

  test "purchasing via turbo stream updates points and inventory" do
    @student.update!(points: 100)
    login_as @student

    post purchases_path, params: { shop_item_id: @food.id }, as: :turbo_stream

    assert_response :success
    assert_match "points_balance", response.body
  end

  test "insufficient balance is rejected with shortage message and unchanged committed balance" do
    @student.update!(points: 10)
    login_as @student

    post purchases_path, params: { shop_item_id: @food.id }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "포인트가 부족해요", response.body
    assert_equal 10, @student.reload.points, "실패 시 커밋된 잔액은 그대로여야 한다"
    assert_equal 0, @student.purchases.count, "실패한 구매 행은 남지 않는다"
  end

  # 구매 트랜잭션 정합: 원자 차감이 실패(경쟁 패배자)하면 롤백돼 무료 아이템도, 포인트 유실도 없다.
  # 컨트롤러 #buy 의 트랜잭션 패턴과 동일 — precheck 가 아니라 원자 가드가 최종 권위다.
  test "a failed atomic spend rolls back the purchase (no free item, no point loss)" do
    @student.update!(points: 30)
    pricey = ShopItem.create!(name: "비싼 배경", category: :decoration, cost: 40, consumable: false, effect: {})

    ok = false
    @student.transaction do
      if @student.spend_points!(pricey.cost)
        @student.purchases.create!(shop_item: pricey, quantity: 1, bought_at: Time.current)
        ok = true
      else
        raise ActiveRecord::Rollback
      end
    end

    assert_not ok
    assert_equal 30, @student.reload.points, "실패한 차감은 포인트를 잃지 않는다"
    assert_equal 0, @student.purchases.where(shop_item: pricey).count, "실패한 구매 행은 남지 않는다"
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
