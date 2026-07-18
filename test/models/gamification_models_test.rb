require "test_helper"

# Enum + association coverage for the P4.8/P4.11 data models.
class GamificationModelsTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "게임화초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "게임화학생", password: "password")
  end

  test "ShopItem category enum defines five categories" do
    assert_equal(
      { "food" => 0, "evolution_stone" => 1, "care" => 2, "decoration" => 3, "accessory" => 4 },
      ShopItem.categories
    )
  end

  test "Purchase belongs to user and shop_item" do
    item = ShopItem.create!(name: "간식", category: :food)
    purchase = Purchase.create!(user: @user, shop_item: item, quantity: 2, bought_at: Time.current)
    assert_equal @user, purchase.user
    assert_equal item, purchase.shop_item
    assert_equal 2, purchase.quantity
  end

  test "Purchase is unique per user and shop_item" do
    item = ShopItem.create!(name: "장식", category: :decoration)
    Purchase.create!(user: @user, shop_item: item, quantity: 1, bought_at: Time.current)
    assert_raises(ActiveRecord::RecordNotUnique) do
      Purchase.create!(user: @user, shop_item: item, quantity: 1, bought_at: Time.current)
    end
  end

  test "Challenge scope enum defines global and school" do
    assert_equal({ "global" => 0, "school" => 1 }, Challenge.scopes)
    assert Challenge.create!(title: "전역").global?
    assert Challenge.create!(title: "학교", scope: :school, school: @school).school?
  end

  test "Season scope enum defines global and school" do
    assert_equal({ "global" => 0, "school" => 1 }, Season.scopes)
    assert Season.create!(name: "여름 시즌").global?
  end

  test "Mission belongs to classroom and optional book" do
    # menu_refactor 심화: title·start_date·end_date 는 이제 필수 검증(모델 재설계).
    mission = Mission.create!(classroom: @classroom, title: "미션",
                              start_date: Date.current, end_date: Date.current + 7)
    assert_equal @classroom, mission.classroom
    assert_nil mission.book
  end
end
