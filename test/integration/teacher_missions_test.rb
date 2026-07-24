require "test_helper"

# P6.2 교사 미션 CRUD + 경계 인가.
class TeacherMissionsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "미션학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "미션담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @other_teacher = User.create!(school: @school, classroom: @other_classroom, name: "미션타담임", role: :teacher, password: "password")
    @other_classroom.update!(teacher: @other_teacher)

    @student = User.create!(school: @school, classroom: @classroom, name: "미션학생", password: "password")
  end

  test "create makes a mission for the담임's classroom" do
    login_as @teacher
    assert_difference -> { Mission.count }, 1 do
      post teacher_missions_path, params: { mission: { title: "가을 독서 미션", start_date: "2026-09-01", end_date: "2026-09-30" } }
    end
    assert_equal @classroom.id, Mission.order(:created_at).last.classroom_id
  end

  test "index lists missions" do
    Mission.create!(classroom: @classroom, title: "겨울 미션", start_date: Date.current, end_date: Date.current + 7)
    login_as @teacher
    get teacher_missions_path
    assert_response :success
    assert_match "겨울 미션", response.body
  end

  test "update edits a mission" do
    mission = Mission.create!(classroom: @classroom, title: "원제목", start_date: Date.current, end_date: Date.current + 7)
    login_as @teacher
    patch teacher_mission_path(mission), params: { mission: { title: "새제목" } }
    assert_equal "새제목", mission.reload.title
  end

  test "destroy removes a mission" do
    mission = Mission.create!(classroom: @classroom, title: "삭제미션", start_date: Date.current, end_date: Date.current + 7)
    login_as @teacher
    assert_difference -> { Mission.count }, -1 do
      delete teacher_mission_path(mission)
    end
  end

  test "a non-담임 teacher cannot edit another classroom's mission" do
    mission = Mission.create!(classroom: @classroom, title: "보호미션", start_date: Date.current, end_date: Date.current + 7)
    login_as @other_teacher
    patch teacher_mission_path(mission), params: { mission: { title: "침입" } }
    assert_response :forbidden
    assert_equal "보호미션", mission.reload.title
  end

  test "a student is forbidden from missions management" do
    login_as @student
    get teacher_missions_path
    assert_response :forbidden
  end

  # --- PR4: 목표·발행·잠금 ---

  test "create builds mission goals and reward points" do
    login_as @teacher
    post teacher_missions_path, params: { mission: {
      title: "목표 미션", start_date: Date.current.to_s, end_date: (Date.current + 7).to_s,
      reward_points: 80, goals: { approved_reports: 3, game_plays: 2 }
    } }
    mission = Mission.order(:created_at).last
    assert mission.draft?
    assert_equal 80, mission.reward_points
    assert_equal %w[approved_reports game_plays].sort, mission.mission_goals.map(&:goal_type).sort
    assert_equal 3, mission.mission_goals.find_by(goal_type: :approved_reports).target_count
  end

  test "target 0 goal is excluded" do
    login_as @teacher
    post teacher_missions_path, params: { mission: {
      title: "부분 목표", start_date: Date.current.to_s, end_date: (Date.current + 7).to_s,
      goals: { approved_reports: 2, game_plays: 0 }
    } }
    mission = Mission.order(:created_at).last
    assert_equal [ "approved_reports" ], mission.mission_goals.map(&:goal_type)
  end

  test "new form renders per-goal book pickers" do
    login_as @teacher
    get new_teacher_mission_path
    assert_response :success
    assert_match "mission[goal_books][approved_reports]", response.body
    assert_match "mission[goal_books][game_plays]", response.body
    assert_match "특정 책 지정", response.body
    assert_match "같은 양의 포인트와 경험치", response.body
  end

  test "edit form prefills the pinned books" do
    book = Book.create!(title: "지정된 책", category: :recommended)
    mission = Mission.create!(classroom: @classroom, title: "수정용", start_date: Date.current, end_date: Date.current + 7)
    goal = mission.mission_goals.create!(goal_type: :approved_reports, target_count: 1)
    goal.books << book
    login_as @teacher
    get edit_teacher_mission_path(mission)
    assert_response :success
    assert_match "지정된 책", response.body # 프리필 칩
  end

  test "create can pin goals to multiple specific books (any-of allowlist)" do
    report_book = Book.create!(title: "독후감 지정책", category: :recommended)
    report_book2 = Book.create!(title: "독후감 지정책2", category: :recommended)
    game_book = Book.create!(title: "게임 지정책", category: :classic)
    login_as @teacher
    post teacher_missions_path, params: { mission: {
      title: "도서 지정 미션", start_date: Date.current.to_s, end_date: (Date.current + 7).to_s,
      goals: { approved_reports: 1, game_plays: 1 },
      goal_books: {
        approved_reports: { ids: [ report_book.id, report_book2.id ] },
        game_plays: { ids: [ game_book.id ] }
      }
    } }
    mission = Mission.order(:created_at).last
    assert_equal [ report_book.id, report_book2.id ].sort,
      mission.mission_goals.find_by(goal_type: :approved_reports).books.map(&:id).sort
    assert_equal [ game_book.id ], mission.mission_goals.find_by(goal_type: :game_plays).books.map(&:id)
  end

  test "blank goal books means any book (no pinned books)" do
    login_as @teacher
    post teacher_missions_path, params: { mission: {
      title: "아무책 미션", start_date: Date.current.to_s, end_date: (Date.current + 7).to_s,
      goals: { approved_reports: 1 }
    } }
    mission = Mission.order(:created_at).last
    assert_empty mission.mission_goals.find_by(goal_type: :approved_reports).books
  end

  test "goal books are server-validated: searched-cache or forged ids are dropped" do
    searched = Book.create!(title: "검색캐시책", category: :searched)
    login_as @teacher
    post teacher_missions_path, params: { mission: {
      title: "위조 미션", start_date: Date.current.to_s, end_date: (Date.current + 7).to_s,
      goals: { approved_reports: 1, game_plays: 1 },
      goal_books: {
        approved_reports: { ids: [ searched.id ] },
        game_plays: { ids: [ 999_999 ] }
      }
    } }
    mission = Mission.order(:created_at).last
    assert_empty mission.mission_goals.find_by(goal_type: :approved_reports).books # searched 제외
    assert_empty mission.mission_goals.find_by(goal_type: :game_plays).books        # 미존재 id 제외
  end

  test "publish transitions to published and auto-assigns classroom students" do
    mission = Mission.new(classroom: @classroom, title: "발행미션", reward_points: 30,
                          start_date: Date.current, end_date: Date.current + 7)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    mission.save!
    login_as @teacher
    post publish_teacher_mission_path(mission)
    assert mission.reload.published?
    assert MissionParticipation.exists?(mission: mission, user: @student)
  end

  test "publish without goals keeps draft with alert" do
    mission = Mission.create!(classroom: @classroom, title: "무목표", start_date: Date.current, end_date: Date.current + 7)
    login_as @teacher
    post publish_teacher_mission_path(mission)
    assert mission.reload.draft?
    assert_not MissionParticipation.exists?(mission: mission)
  end

  test "published mission can be fully edited by the owning teacher" do
    mission = Mission.new(classroom: @classroom, title: "잠금해제미션", start_date: Date.current, end_date: Date.current + 7)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 2)
    mission.save!
    mission.publish!
    login_as @teacher
    patch teacher_mission_path(mission), params: { mission: {
      title: "새 제목", start_date: (Date.current + 10).to_s, end_date: (Date.current + 40).to_s,
      goals: { approved_reports: 9 }
    } }
    mission.reload
    assert_equal "새 제목", mission.title                          # 제목 수정됨
    assert_equal Date.current + 10, mission.start_date            # 기간도 수정됨(잠금 해제)
    assert_equal 9, mission.mission_goals.first.target_count       # 목표도 수정됨
  end

  test "published mission can be destroyed by the owning teacher" do
    mission = Mission.new(classroom: @classroom, title: "발행삭제", start_date: Date.current, end_date: Date.current + 7)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    mission.save!
    mission.publish!
    login_as @teacher
    assert_difference -> { Mission.count }, -1 do
      delete teacher_mission_path(mission)
    end
  end

  test "non-담임 teacher cannot publish another classroom's mission" do
    mission = Mission.new(classroom: @classroom, title: "타학급발행", start_date: Date.current, end_date: Date.current + 7)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    mission.save!
    login_as @other_teacher
    post publish_teacher_mission_path(mission)
    assert_response :forbidden
    assert mission.reload.draft?
  end

  test "status filter scopes the list" do
    draft = Mission.create!(classroom: @classroom, title: "초안하나", start_date: Date.current, end_date: Date.current + 7)
    published = Mission.new(classroom: @classroom, title: "발행하나", start_date: Date.current, end_date: Date.current + 7)
    published.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    published.save!
    published.publish!
    login_as @teacher
    get teacher_missions_path(status: "draft")
    assert_match "초안하나", response.body
    assert_no_match(/발행하나/, response.body)
  end

  private
end
