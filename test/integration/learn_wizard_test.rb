require "test_helper"

# P5.5 — 단계 학습 위저드 5단계: 단계 진행, 이탈 후 복귀(세션 복원), 완료 시 독후감 초안 연결.
class LearnWizardTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "위저드초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "위저드학생", password: "password")
  end

  test "index starts at step 1 and injects the achievement standard" do
    login_as @student
    get learn_index_path
    assert_response :success
    assert_select "h1", /단계 학습/
    assert_includes response.body, "[6국02-05]"
  end

  test "advancing moves through the five steps in order" do
    login_as @student

    post advance_learn_index_path, params: { step: 1, answer: "마당을 나온 암탉을 읽었어요." }
    assert_redirected_to learn_index_path
    follow_redirect!
    assert_includes response.body, "[6국05-03]" # 2단계 성취기준

    post advance_learn_index_path, params: { step: 2, answer: "잎싹이 알을 품는 이야기." }
    follow_redirect!
    assert_includes response.body, "[6국05-04]" # 3단계 성취기준
  end

  test "progress is restored after leaving and returning (session persistence)" do
    login_as @student
    post advance_learn_index_path, params: { step: 1, answer: "책 고르기 답" }
    post advance_learn_index_path, params: { step: 2, answer: "줄거리 답" }

    # 다른 화면에 다녀와도(이탈) 세션 진행이 유지된다.
    get root_path
    get learn_index_path
    assert_response :success
    assert_includes response.body, "3단계"
    assert_includes response.body, "책 고르기 답" # 앞 단계 답안 요약 복원
  end

  test "completing the wizard prefills a report draft from the five steps" do
    login_as @student
    answers = {
      1 => "『마당을 나온 암탉』을 골랐어요.",
      2 => "잎싹의 줄거리.",
      3 => "가장 인상 깊은 장면.",
      4 => "내 생각과 느낌.",
      5 => "내 삶과의 연결."
    }
    answers.first(4).each { |step, answer| post advance_learn_index_path, params: { step: step, answer: answer } }

    post advance_learn_index_path, params: { step: 5, answer: answers[5] }
    assert_response :redirect
    follow_redirect!

    assert_response :success
    assert_select "form"
    # 5단계 답안이 독후감 본문 초안으로 프리필된다.
    assert_includes response.body, "삶과 연결"
    assert_includes response.body, "내 삶과의 연결."
    # 위저드 진행은 완료 후 초기화된다.
    get learn_index_path
    assert_includes response.body, "1단계"
  end

  test "wizard requires login" do
    get learn_index_path
    assert_redirected_to new_session_path
  end

  # 성취기준은 학생 학년군 것만 보여 준다 — 1~4학년에게 5~6학년 코드를 보이지 않는다.
  test "shows the achievement standard of the student's own grade band" do
    { 2 => %w[[2국02-05] [2국02-03]], 3 => %w[[4국02-06] [4국02-02]] }.each do |grade, (step1, step2)|
      classroom = Classroom.create!(school: @school, grade: grade, class_no: 9)
      student = User.create!(school: @school, classroom: classroom, name: "위저드#{grade}학년", password: "password")
      login_as student

      get learn_index_path
      assert_includes response.body, step1
      assert_not_includes response.body, "[6국", "#{grade}학년에게 5~6학년 성취기준을 보이지 않는다"

      post advance_learn_index_path, params: { step: 1, answer: "책 고르기 답" }
      follow_redirect!
      assert_includes response.body, step2
      delete session_path
    end
  end

  test "a student without a classroom sees the lowest grade band, not 5~6" do
    student = User.create!(school: @school, name: "학급없는학생", password: "password")
    login_as student

    get learn_index_path
    assert_includes response.body, "[2국02-05]"
    assert_not_includes response.body, "[6국"
  end

  # 단계마다 세 학년군 코드가 모두 있고, 각 코드가 그 학년군 첨삭 목록(고시 원문) 안에 있다.
  test "every step has a standard from each band's own curriculum list" do
    LearnController::STEPS.each do |step|
      assert_equal %i[g12 g34 g56], step[:codes].keys
      step[:codes].each do |band, code|
        allowed = ReadingDomain::CURRICULUM_STANDARDS_BY_BAND.fetch(band).values.flatten(1).map(&:first)
        assert_includes allowed, code, "#{step[:title]} #{band}"
      end
    end
  end
end
