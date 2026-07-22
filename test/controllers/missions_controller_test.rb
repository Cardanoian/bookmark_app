require "test_helper"

# 미션 학생 열람 전용 상세(challenge-mission-detail-pages Step 3). 자기 학급 발행 미션은 200 +
# 상세·지정 도서·진행상황 노출, 타 학급/미발행 미션은 학급 경계 인가로 403.
class MissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "미션상세초")
    @class1 = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @class2 = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @teacher = User.create!(school: @school, name: "상세담임", role: :teacher, email: "dt@example.com", password: "password")
    @class1.update!(teacher: @teacher)
    @student1 = User.create!(school: @school, classroom: @class1, name: "상세학생1", password: "password")
    @student2 = User.create!(school: @school, classroom: @class2, name: "상세학생2", password: "password")

    @book = Book.create!(title: "미션 지정 도서", author: "지은이")
    @mission = Mission.new(classroom: @class1, title: "우리 반 가을 미션", description: "가을엔 책 읽자",
                           status: :published, start_date: Date.current, end_date: Date.current + 7,
                           reward_points: 30)
    @mission.mission_goals.build(goal_type: :approved_reports, target_count: 2)
    @mission.save!
    @mission.mission_goals.first.books << @book
  end

  test "student sees own classroom published mission detail with book list and progress" do
    login_as @student1
    get mission_path(@mission)
    assert_response :success
    assert_match "우리 반 가을 미션", response.body
    assert_match "가을엔 책 읽자", response.body
    assert_match "미션 지정 도서", response.body
    assert_match "미션 진행상황", response.body
  end

  test "student from another classroom is forbidden" do
    login_as @student2
    get mission_path(@mission)
    assert_response :forbidden
  end

  test "unpublished (draft) mission is forbidden for a student" do
    draft = Mission.create!(classroom: @class1, title: "초안 미션", status: :draft,
                            start_date: Date.current, end_date: Date.current + 7)
    login_as @student1
    get mission_path(draft)
    assert_response :forbidden
  end

  test "담임 teacher sees the mission detail (no student progress section)" do
    login_as @teacher
    get mission_path(@mission)
    assert_response :success
    assert_match "우리 반 가을 미션", response.body
    # 교직원에겐 @progress 가 nil 이라 학생 진행상황 섹션이 숨겨진다(nil 가드).
    assert_no_match "미션 진행상황", response.body
  end
end
