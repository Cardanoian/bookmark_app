require "test_helper"

# 뒷이야기 코멘트 검토(2026-09-19). 책갈피 도우미(AI) 코멘트는 담임이 승인해야 작성 학생에게 보인다.
# 담임 학급 경계·검토 대기 범위(코멘트 잡이 끝난 글만)·승인/수정 저장·빈 코멘트 거부·학생 화면 반영·
# 방송·진입점(네비·대시보드)을 고정한다. 학생 화면 쪽 게이트는 games_sequel_test 가 함께 본다.
class TeacherSequelReviewsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "뒷이야기검토학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @teacher = User.create!(school: @school, name: "뒷이야기담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 4, class_no: 2)
    @other_teacher = User.create!(school: @school, name: "다른반담임", role: :teacher, password: "password")
    @other_classroom.update!(teacher: @other_teacher)

    @student = User.create!(school: @school, classroom: @classroom, name: "이야기학생", password: "password")
    @outsider = User.create!(school: @school, classroom: @other_classroom, name: "다른반학생", password: "password")
    @book = Book.create!(title: "검토할뒷이야기책", author: "지은이", category: :recommended)

    @sequel = create_sequel(@student, body: "주인공은 바다 건너 새 친구를 만나러 떠났어요.",
                                      ai_status: :done, ai_comment: "바다를 건너는 장면이 생생해요!")
  end

  test "the queue lists the teacher's own finished, unapproved sequels only" do
    working = create_sequel(@student, body: "아직 도우미가 읽고 있는 뒷이야기예요.", ai_status: :processing)
    other = create_sequel(@outsider, body: "다른 반 학생이 쓴 뒷이야기예요.", ai_status: :done, ai_comment: "다른 반 코멘트")

    login_as @teacher
    get teacher_sequel_reviews_path
    assert_response :success
    assert_includes response.body, "주인공은 바다 건너 새 친구를 만나러 떠났어요."
    assert_select "textarea[name='book_sequel[comment]']", text: "바다를 건너는 장면이 생생해요!"
    assert_not_includes response.body, working.body, "코멘트 잡이 도는 중인 글은 아직 검토 대상이 아니다"
    assert_not_includes response.body, other.body, "다른 반 글은 보이지 않는다"
    assert_select "a[aria-current='page']", text: "미검토 1"
  end

  test "approving an unchanged comment shows it to the author, not to classmates" do
    login_as @teacher
    assert_turbo_stream_broadcasts(@sequel) do
      post approve_teacher_sequel_review_path(@sequel), params: { book_sequel: { comment: "바다를 건너는 장면이 생생해요!" } }
    end
    assert_redirected_to teacher_sequel_reviews_path(status: "pending")
    follow_redirect!
    assert_includes response.body, "승인했어요"

    @sequel.reload
    assert @sequel.reviewed?
    assert_equal @teacher, @sequel.reviewed_by
    assert_nil @sequel.teacher_comment

    login_as @student
    get games_sequel_play_path(book_id: @book.id)
    assert_includes response.body, "바다를 건너는 장면이 생생해요!"

    peer = User.create!(school: @school, classroom: @classroom, name: "같은반친구", password: "password")
    login_as peer
    get games_sequel_play_path(book_id: @book.id)
    assert_includes response.body, @sequel.body
    assert_not_includes response.body, "바다를 건너는 장면이 생생해요!", "친구는 승인된 코멘트도 보지 않는다"
  end

  test "an edited comment reaches the student instead of the AI original" do
    login_as @teacher
    post approve_teacher_sequel_review_path(@sequel), params: { book_sequel: { comment: "새 친구를 만나는 장면을 더 듣고 싶어요." } }

    assert_equal "새 친구를 만나는 장면을 더 듣고 싶어요.", @sequel.reload.teacher_comment

    login_as @student
    get games_sequel_play_path(book_id: @book.id)
    assert_includes response.body, "새 친구를 만나는 장면을 더 듣고 싶어요."
    assert_not_includes response.body, "바다를 건너는 장면이 생생해요!"
  end

  test "a blank comment is rejected with a reason and nothing is approved" do
    login_as @teacher
    post approve_teacher_sequel_review_path(@sequel), params: { book_sequel: { comment: "   " } }

    assert_response :unprocessable_entity
    assert_includes response.body, "코멘트가 비어 있어요"
    assert_includes response.body, "#{@student.name} 학생의", "어느 글의 오류인지 알린다"
    assert_not @sequel.reload.reviewed?
  end

  test "a forged non-hash comment field ends in 422, not 500" do
    login_as @teacher
    post approve_teacher_sequel_review_path(@sequel), params: { book_sequel: "abc" }
    assert_response :unprocessable_entity

    post approve_teacher_sequel_review_path(@sequel), params: { book_sequel: { comment: [ "a", "b" ] } }
    assert_response :unprocessable_entity
    assert_not @sequel.reload.reviewed?
  end

  test "a teacher writes the comment when the helper could not make one" do
    failed = create_sequel(@student, body: "도우미가 코멘트를 못 만든 뒷이야기예요.", ai_status: :failed)

    login_as @teacher
    get teacher_sequel_reviews_path
    assert_includes response.body, "코멘트를 만들지 못했어요"

    post approve_teacher_sequel_review_path(failed), params: { book_sequel: { comment: "끝까지 쓴 점이 멋져요." } }
    assert failed.reload.comment_visible?

    login_as @student
    get games_sequel_play_path(book_id: @book.id)
    feedback_id = ActionView::RecordIdentifier.dom_id(failed, :feedback)
    assert_select "##{feedback_id} p.font-semibold", text: /\A\s*선생님\s*\z/
    assert_select "##{feedback_id}", text: /책갈피 도우미/, count: 0
    assert_select "##{feedback_id}", text: /끝까지 쓴 점이 멋져요\./
  end

  test "a comment made public before approval existed is not labelled as teacher-checked" do
    legacy = create_sequel(@student, body: "승인 제도 전에 코멘트가 공개된 뒷이야기예요.",
                                     ai_status: :done, ai_comment: "예전 코멘트예요.", reviewed_at: 1.month.ago)

    login_as @student
    get games_sequel_play_path(book_id: @book.id)
    assert_select "##{ActionView::RecordIdentifier.dom_id(legacy, :feedback)}", text: /예전 코멘트예요\./
    assert_select "##{ActionView::RecordIdentifier.dom_id(legacy, :feedback)}", text: /선생님이 확인/, count: 0

    login_as @teacher
    get teacher_sequel_reviews_path(status: "reviewed")
    assert_select "##{ActionView::RecordIdentifier.dom_id(legacy, :review)} .badge", text: "예전에 공개된 코멘트"
  end

  test "a sequel whose comment is still being written cannot be approved" do
    working = create_sequel(@student, body: "아직 도우미가 읽고 있는 뒷이야기예요.", ai_status: :processing)

    login_as @teacher
    post approve_teacher_sequel_review_path(working), params: { book_sequel: { comment: "먼저 승인" } }
    assert_redirected_to teacher_sequel_reviews_path(status: "pending")
    assert_not working.reload.reviewed?
  end

  test "an approved comment can be fixed again from the reviewed tab without changing the approval time" do
    @sequel.update!(reviewed_at: 2.days.ago, reviewed_by: @teacher)

    login_as @teacher
    get teacher_sequel_reviews_path(status: "reviewed")
    assert_response :success
    assert_includes response.body, @sequel.body
    assert_select "input[type=submit][value='고쳐서 저장']"

    approved_at = @sequel.reviewed_at
    post approve_teacher_sequel_review_path(@sequel, status: "reviewed"), params: { book_sequel: { comment: "고친 코멘트예요." } }
    assert_redirected_to teacher_sequel_reviews_path(status: "reviewed")
    follow_redirect!
    assert_includes response.body, "코멘트를 고쳤어요"
    assert_equal "고친 코멘트예요.", @sequel.reload.teacher_comment
    assert_equal approved_at.to_i, @sequel.reviewed_at.to_i
  end

  test "another classroom's teacher cannot approve" do
    login_as @other_teacher
    post approve_teacher_sequel_review_path(@sequel), params: { book_sequel: { comment: "남의 반 승인" } }
    assert_response :forbidden
    assert_not @sequel.reload.reviewed?
  end

  test "an unknown status falls back to the pending tab, and an empty later page goes back" do
    login_as @teacher
    get teacher_sequel_reviews_path(status: "bogus")
    assert_response :success
    assert_select "a[aria-current='page']", text: "미검토 1"

    get teacher_sequel_reviews_path(status: "pending", page: 2)
    assert_redirected_to teacher_sequel_reviews_path(status: "pending")
  end

  test "a teacher without a classroom sees an empty queue and cannot approve" do
    loner = User.create!(school: @school, name: "학급없는교사", role: :teacher, password: "password")
    login_as loner
    get teacher_sequel_reviews_path
    assert_response :success
    assert_not_includes response.body, @sequel.body

    post approve_teacher_sequel_review_path(@sequel), params: { book_sequel: { comment: "승인" } }
    assert_response :forbidden
    assert_not @sequel.reload.reviewed?
  end

  test "students cannot open the review queue" do
    login_as @student
    get teacher_sequel_reviews_path
    assert_response :forbidden
  end

  test "the teacher nav and dashboard lead to the queue" do
    login_as @teacher
    get teacher_dashboard_path
    assert_response :success
    assert_select "a[href='#{teacher_sequel_reviews_path}']", text: /뒷이야기 검토/
    assert_includes response.body, "뒷이야기 코멘트 검토 (1)"

    @sequel.update!(reviewed_at: Time.current)
    get teacher_dashboard_path
    assert_not_includes response.body, "뒷이야기 코멘트 검토 (", "대기가 없으면 대시보드 알림을 숨긴다"
  end

  private

  def create_sequel(user, body:, **attrs)
    BookSequel.create!(user: user, book: @book, classroom: user.classroom, body: body, **attrs)
  end
end
