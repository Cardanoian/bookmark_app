require "test_helper"

# 단계 학습 위저드 진행(학생마다 한 행). 흐름은 test/integration/learn_wizard_test.rb 가 본다.
class LearnWizardProgressTest < ActiveSupport::TestCase
  setup do
    school = School.create!(name: "진행행학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    @student = User.create!(school: school, classroom: classroom, name: "진행행학생", password: "password")
  end

  test "starts at step 1 with no answers" do
    progress = LearnWizardProgress.create!(user: @student)
    assert_equal 1, progress.step
    assert_equal({}, progress.answers)
  end

  test "a student has only one progress row" do
    LearnWizardProgress.create!(user: @student)
    assert_not LearnWizardProgress.new(user: @student).valid?
    assert_raises(ActiveRecord::RecordNotUnique) { LearnWizardProgress.new(user: @student).save!(validate: false) }
  end

  # 계정 연동은 placeholder 계정을 raw delete_all 로 지운다 — 콜백 없이도 DB FK(CASCADE)가 함께 지운다.
  test "is removed with its user, even by a raw delete" do
    LearnWizardProgress.create!(user: @student, step: 3, answers: { "1" => "책 제목" })

    User.where(id: @student.id).delete_all
    assert_not LearnWizardProgress.exists?(user_id: @student.id)
  end
end
