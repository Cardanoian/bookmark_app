require "test_helper"

# 학생 획득 뱃지(#5 미테스트 모델 보강). (user, badge) 유일성으로 중복 획득 방지.
class UserBadgeTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "뱃지학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "뱃지학생", password: "password")
    @badge = Badge.create!(key: "first", name: "첫 독후감")
  end

  test "belongs to a user and a badge" do
    ub = UserBadge.create!(user: @user, badge: @badge)
    assert_equal @user, ub.user
    assert_equal @badge, ub.badge
  end

  test "the same badge cannot be granted twice to one user (model validation)" do
    UserBadge.create!(user: @user, badge: @badge)
    duplicate = UserBadge.new(user: @user, badge: @badge)
    assert_not duplicate.valid?
    assert duplicate.errors[:badge_id].any?
  end

  test "different users can each hold the same badge" do
    other = User.create!(school: @school, classroom: @classroom, name: "다른뱃지학생", password: "password")
    UserBadge.create!(user: @user, badge: @badge)
    assert UserBadge.new(user: other, badge: @badge).valid?
  end
end
