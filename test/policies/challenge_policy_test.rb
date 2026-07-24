require "test_helper"

# 챌린지 정책. 열람=로그인 사용자, 참여=학생, 관리(생성·수정·삭제)=교직원.
# 관리 학교 경계: 총괄=전권(전국·모든 학교), 교사·사서·교무=우리 학교의 '학교 스코프' 챌린지만.
class ChallengePolicyTest < ActiveSupport::TestCase
  setup do
    @school_a = School.create!(name: "챌린지정책A초")
    @school_b = School.create!(name: "챌린지정책B초")
    @room_a = Classroom.create!(school: @school_a, grade: 5, class_no: 1)

    @student = User.create!(school: @school_a, classroom: @room_a, name: "정책학생", role: :student, password: "password")
    @teacher_a = User.create!(school: @school_a, name: "정책교사A", role: :teacher, password: "password")
    @teacher_b = User.create!(school: @school_b, name: "정책교사B", role: :teacher, password: "password")
    @librarian_a = User.create!(school: @school_a, name: "정책사서A", role: :librarian, password: "password")
    @school_admin_a = User.create!(school: @school_a, name: "정책교무A", role: :school_admin, password: "password")
    @superadmin = User.create!(name: "정책총괄", role: :superadmin, password: "password")

    @global = Challenge.create!(title: "전국 챌린지", scope: :global)
    @school_a_challenge = Challenge.create!(title: "A학교 챌린지", scope: :school, school: @school_a)
    @school_b_challenge = Challenge.create!(title: "B학교 챌린지", scope: :school, school: @school_b)
  end

  test "index?/show? allow any logged-in role but not anonymous" do
    [ @student, @teacher_a, @librarian_a, @school_admin_a, @superadmin ].each do |user|
      assert ChallengePolicy.new(user, @global).index?, "#{user.role} should view index"
      assert ChallengePolicy.new(user, @global).show?, "#{user.role} should view show"
    end
    assert_not ChallengePolicy.new(nil, @global).index?
    assert_not ChallengePolicy.new(nil, @global).show?
  end

  test "join? is student-only" do
    assert ChallengePolicy.new(@student, @global).join?
    assert_not ChallengePolicy.new(@teacher_a, @global).join?
    assert_not ChallengePolicy.new(@superadmin, @global).join?
    assert_not ChallengePolicy.new(nil, @global).join?
  end

  test "manage?/new?/create? allow all staff but not students or anonymous" do
    [ @teacher_a, @librarian_a, @school_admin_a, @superadmin ].each do |user|
      assert ChallengePolicy.new(user, Challenge.new).create?, "#{user.role} should create"
      assert ChallengePolicy.new(user, Challenge.new).new?, "#{user.role} should reach new"
    end
    assert_not ChallengePolicy.new(@student, Challenge.new).create?
    assert_not ChallengePolicy.new(nil, Challenge.new).create?
  end

  test "superadmin may edit/destroy any challenge (global or any school)" do
    [ @global, @school_a_challenge, @school_b_challenge ].each do |challenge|
      assert ChallengePolicy.new(@superadmin, challenge).edit?
      assert ChallengePolicy.new(@superadmin, challenge).update?
      assert ChallengePolicy.new(@superadmin, challenge).destroy?
    end
  end

  test "school staff may edit/destroy only their own school's school-scoped challenge" do
    [ @teacher_a, @librarian_a, @school_admin_a ].each do |user|
      assert ChallengePolicy.new(user, @school_a_challenge).edit?, "#{user.role} should manage own school"
      assert ChallengePolicy.new(user, @school_a_challenge).destroy?, "#{user.role} should delete own school"

      assert_not ChallengePolicy.new(user, @global).edit?, "#{user.role} must not manage global"
      assert_not ChallengePolicy.new(user, @global).destroy?, "#{user.role} must not delete global"
      assert_not ChallengePolicy.new(user, @school_b_challenge).edit?, "#{user.role} must not cross school boundary"
      assert_not ChallengePolicy.new(user, @school_b_challenge).destroy?, "#{user.role} must not delete other school"
    end
  end

  test "students may not edit/destroy any challenge" do
    [ @global, @school_a_challenge ].each do |challenge|
      assert_not ChallengePolicy.new(@student, challenge).edit?
      assert_not ChallengePolicy.new(@student, challenge).destroy?
    end
  end

  test "Scope gives superadmin everything and others global plus own school" do
    superadmin_scope = ChallengePolicy::Scope.new(@superadmin, Challenge.all).resolve
    assert_includes superadmin_scope, @school_b_challenge

    [ @student, @teacher_a, @librarian_a, @school_admin_a ].each do |user|
      resolved = ChallengePolicy::Scope.new(user, Challenge.all).resolve
      assert_includes resolved, @global, "#{user.role} should see global"
      assert_includes resolved, @school_a_challenge, "#{user.role} should see own school"
      assert_not_includes resolved, @school_b_challenge, "#{user.role} must not see other school"
    end

    assert_empty ChallengePolicy::Scope.new(nil, Challenge.all).resolve
  end
end
