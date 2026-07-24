require "test_helper"

# 계정 연동 학생 셀프서브 정책(account_linking_seasons_plan §Phase 3) — 학급 소속 학생만.
class AccountLinkPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "정책초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "정책학생", password: "password")
  end

  test "학급 소속 학생은 new?/preview?/confirm? 를 허용한다" do
    policy = AccountLinkPolicy.new(@student, :account_link)

    assert policy.new?
    assert policy.preview?
    assert policy.confirm?
  end

  test "학급이 없는 학생은 거부한다" do
    loner = User.create!(school: @school, name: "무학급학생", password: "password")
    policy = AccountLinkPolicy.new(loner, :account_link)

    assert_not policy.new?
    assert_not policy.preview?
    assert_not policy.confirm?
  end

  test "교사는 거부한다" do
    teacher = User.create!(school: @school, classroom: @classroom, name: "정책교사",
                           role: :teacher, password: "password", email: "policy@example.com")
    policy = AccountLinkPolicy.new(teacher, :account_link)

    assert_not policy.new?
    assert_not policy.preview?
    assert_not policy.confirm?
  end

  test "비로그인은 거부한다" do
    policy = AccountLinkPolicy.new(nil, :account_link)

    assert_not policy.new?
    assert_not policy.preview?
    assert_not policy.confirm?
  end
end
