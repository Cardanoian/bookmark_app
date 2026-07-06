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

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
