require "test_helper"

# 학생 출제 기여 정책. 작성(출제)은 학급 소속 학생 본인만. 교사·비학급·비로그인은 불가.
# (교사 검토·승인 경계는 Teacher::QuizContributionsController 의 owned_student! 가 강제 — 통합 테스트.)
class QuizContributionPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "기여정책초")
    @room = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @room, name: "정책교사", role: :teacher, password: "password")
    @student = User.create!(school: @school, classroom: @room, name: "정책학생", password: "password")
    @classless = User.create!(school: @school, name: "무학급학생", role: :student, password: "password")
  end

  test "a classroom student may create; a teacher, classless, or anonymous user may not" do
    assert QuizContributionPolicy.new(@student, QuizContribution.new).create?
    assert QuizContributionPolicy.new(@student, QuizContribution.new).new?
    assert_not QuizContributionPolicy.new(@teacher, QuizContribution.new).create?
    assert_not QuizContributionPolicy.new(@classless, QuizContribution.new).create?
    assert_not QuizContributionPolicy.new(nil, QuizContribution.new).create?
  end
end
