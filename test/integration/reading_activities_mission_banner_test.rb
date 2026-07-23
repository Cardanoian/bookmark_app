require "test_helper"

# reading_activity(도서 상세) 미션 문맥 배너 — 이 책 활동이 실제로 미션 진행에 반영되는 목표가
# 있을 때만 노출한다. 특정 도서 지정 목표는 그 도서에서만, 지정 없는(아무 책이나) 목표는 모든
# 책에서 반영되므로, 반영되는 목표 종류만 힌트로 렌더한다.
class ReadingActivitiesMissionBannerTest < ActionDispatch::IntegrationTest
  BANNER = "진행 중인 미션이 있어요".freeze

  setup do
    @school = School.create!(name: "미션배너초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "배너학생", password: "password")
    @target = Book.create!(title: "지정도서", category: :recommended)
    @other  = Book.create!(title: "무관도서", category: :recommended)
    login_as @student
  end

  # 발행(=학급 학생 자동 배정)된 진행 중 미션을 만든다. books 를 지정하면 특정 도서 목표, 비우면 아무 책이나.
  def publish_mission!(title:, goal_type:, books: [])
    mission = Mission.new(classroom: @classroom, title: title, reward_points: 0,
                          start_date: Date.current, end_date: Date.current + 7)
    goal = mission.mission_goals.build(goal_type: goal_type, target_count: 3)
    books.each { |b| goal.mission_goal_books.build(book: b) }
    mission.save!
    mission.publish!
    mission
  end

  test "특정 도서 지정 미션은 그 도서가 아닌 책에서 배너를 띄우지 않는다" do
    publish_mission!(title: "게임 미션", goal_type: :game_plays, books: [ @target ])

    get reading_activity_path(book_id: @other.id)

    assert_response :success
    assert_no_match BANNER, response.body
  end

  test "특정 도서 지정 미션은 그 도서 페이지에서 반영 목표 힌트와 함께 배너를 띄운다" do
    publish_mission!(title: "게임 미션", goal_type: :game_plays, books: [ @target ])

    get reading_activity_path(book_id: @target.id)

    assert_response :success
    assert_match BANNER, response.body
    assert_match "독서 게임 활동이 미션 진행에 반영돼요", response.body
  end

  test "아무 책이나 인정하는 목표 미션은 모든 책에서 배너를 띄운다" do
    publish_mission!(title: "자유 독후감 미션", goal_type: :approved_reports, books: [])

    get reading_activity_path(book_id: @other.id)

    assert_response :success
    assert_match BANNER, response.body
    assert_match "승인 독후감 활동이 미션 진행에 반영돼요", response.body
  end

  test "진행 중 미션이 하나도 없으면 배너가 없다" do
    get reading_activity_path(book_id: @target.id)

    assert_response :success
    assert_no_match BANNER, response.body
  end

  test "이 책이 반영되는 목표의 힌트만 노출한다(혼합 목표)" do
    # 게임 목표는 @target 만 지정, 독후감 목표는 아무 책이나(빈 지정)인 한 미션.
    mission = Mission.new(classroom: @classroom, title: "혼합 미션", reward_points: 0,
                          start_date: Date.current, end_date: Date.current + 7)
    game_goal = mission.mission_goals.build(goal_type: :game_plays, target_count: 3)
    game_goal.mission_goal_books.build(book: @target)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 3) # 아무 책이나
    mission.save!
    mission.publish!

    get reading_activity_path(book_id: @other.id)

    assert_response :success
    assert_match BANNER, response.body
    # @other 는 독후감 목표(아무 책이나)에만 반영되고 게임 목표(@target 지정)에는 반영되지 않는다.
    assert_match "승인 독후감 활동이 미션 진행에 반영돼요", response.body
    assert_no_match "독서 게임 활동이 미션 진행에 반영돼요", response.body
  end
end
