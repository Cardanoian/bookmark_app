require "test_helper"

# 이 책의 내 기록(library_books#show) — 내 서재 책 제목의 목적지. 책 한 권으로 한 본인 활동(독후감·게임 완료·
# 뒷이야기와 담임 승인 코멘트·책 소개·토론 글·낸 문제)을 모으고, 남의 글·숨김 글·미승인 코멘트는 내보내지
# 않으며, 반이 바뀐 뒤에도 예전 학급에서 쓴 글을 보여 준다.
class LibraryBooksTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "내기록초등학교")
    @room_a = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @room_b = Classroom.create!(school: @school, grade: 4, class_no: 2)
    @teacher = User.create!(school: @school, name: "담임", role: :teacher, email: "records_t@example.com", password: "password")
    @room_a.update!(teacher_id: @teacher.id)
    @student = User.create!(school: @school, classroom: @room_a, name: "기록학생", password: "password")
    @peer = User.create!(school: @school, classroom: @room_a, name: "같은반친구", password: "password")
    @book = Book.create!(title: "내기록책", author: "지은이", category: :recommended)
  end

  test "모든 종류의 내 기록을 한 화면에 보여 준다" do
    Report.create!(user: @student, classroom: @room_a, book: @book, body: "내기록 독후감 본문입니다.")
    @student.game_plays.create!(game_type: :quiz, book: @book, played_on: Date.new(2026, 9, 18))
    @student.game_plays.create!(game_type: :sequel, book: @book, played_on: Date.new(2026, 9, 17))
    sequel(@student, "주인공이 새 친구를 만나 모험을 떠났어요.")
    BookIntro.create!(user: @student, book: @book, classroom: @room_a, body: "이 책은 우정 이야기라서 추천해요.")
    topic = Topic.create!(scope: :classroom, classroom: @room_a, book: @book, title: "주인공은 옳았을까", kind: :debate)
    ForumPost.create!(topic: topic, user: @student, text: "저는 옳았다고 생각해요.", stance: :pro)
    contribution(@student, "주인공의 이름은 무엇인가요?")

    login_as @student
    get library_book_path(@book)
    assert_response :success

    assert_select "#book-reports", text: /내기록 독후감 본문입니다/
    assert_select "#book-games [data-game-completion=quiz]", text: /독서 퀴즈.*완료.*2026\.09\.18/m
    assert_select "#book-games [data-game-completion=sequel]", text: /뒷이야기 이어쓰기/
    assert_select "#book-games [data-game-completion=whoami]", 0
    assert_select "#book-sequels", text: /주인공이 새 친구를 만나 모험을 떠났어요/
    assert_select "#book-intros", text: /이 책은 우정 이야기라서 추천해요/
    assert_select "#book-forum-posts", text: /저는 옳았다고 생각해요/
    assert_select "#book-forum-posts a[href=?]", topic_path(topic), text: "주인공은 옳았을까"
    assert_select "#book-forum-posts .badge", text: "찬성"
    assert_select "#book-contributions", text: /주인공의 이름은 무엇인가요/
    assert_select "a[href=?]", reading_activity_path(book_id: @book.id)
  end

  test "뒷이야기 코멘트는 담임이 승인한 뒤에만 보인다" do
    pending = sequel(@student, "승인 전 뒷이야기 본문이에요.", ai_status: :done, ai_comment: "아직비공개인AI코멘트")
    login_as @student

    get library_book_path(@book)
    assert_select "#book-sequels", text: /선생님이 코멘트를 확인하고 있어요/
    assert_no_match "아직비공개인AI코멘트", response.body

    assert pending.approve(by: @teacher, comment: "선생님이 확인한 코멘트")
    get library_book_path(@book)
    assert_select "#book-sequels", text: /선생님이 확인한 코멘트/
  end

  test "다른 학생의 글과 숨김 토론 글은 보이지 않는다" do
    sequel(@peer, "친구가 쓴 뒷이야기 본문이에요.")
    BookIntro.create!(user: @peer, book: @book, classroom: @room_a, body: "친구가 쓴 책 소개 본문이에요.")
    topic = Topic.create!(scope: :classroom, classroom: @room_a, book: @book, title: "자유 토론")
    ForumPost.create!(topic: topic, user: @peer, text: "친구의 토론 글")
    ForumPost.create!(topic: topic, user: @student, text: "숨겨진 내 토론 글", hidden: true)
    ForumPost.create!(topic: topic, user: @student, text: "보이는 내 토론 글")

    login_as @student
    get library_book_path(@book)
    assert_response :success
    assert_no_match "친구가 쓴 뒷이야기", response.body
    assert_no_match "친구가 쓴 책 소개", response.body
    assert_no_match "친구의 토론 글", response.body
    assert_no_match "숨겨진 내 토론 글", response.body
    assert_select "#book-forum-posts", text: /보이는 내 토론 글/
  end

  test "반이 바뀐 뒤에도 예전 학급에서 쓴 뒷이야기가 보이고, 열 수 없는 토론방은 제목만 보인다" do
    sequel(@student, "작년 반에서 쓴 뒷이야기예요.")
    topic = Topic.create!(scope: :classroom, classroom: @room_a, book: @book, title: "작년 반 토론")
    ForumPost.create!(topic: topic, user: @student, text: "작년 반에서 쓴 토론 글")
    @student.update!(classroom: @room_b)

    login_as @student
    get library_book_path(@book)
    assert_select "#book-sequels", text: /작년 반에서 쓴 뒷이야기예요/
    assert_select "#book-forum-posts", text: /작년 반 토론/
    assert_select "#book-forum-posts a[href=?]", topic_path(topic), 0
  end

  test "독서 토론이 꺼진 학급에는 토론 섹션이 없다" do
    AppSetting.create!(key: "feature_flags", value: { "reading_discussion" => false })
    Report.create!(user: @student, classroom: @room_a, book: @book, body: "독후감")
    topic = Topic.create!(scope: :classroom, classroom: @room_a, book: @book, title: "꺼진 토론")
    ForumPost.create!(topic: topic, user: @student, text: "꺼진 학급의 토론 글")

    login_as @student
    get library_book_path(@book)
    assert_response :success
    assert_select "#book-forum-posts", 0
    assert_no_match "꺼진 학급의 토론 글", response.body
  end

  # 체험 시드처럼 글 없이 완료 원장만 있는 뒷이야기·책 소개는 "완료"로 보이지 않는다(보여 줄 글이 없다).
  test "글 없는 뒷이야기·책 소개 완료 기록은 완료 칩을 만들지 않는다" do
    @student.game_plays.create!(game_type: :sequel, book: @book, played_on: Date.current)
    @student.game_plays.create!(game_type: :book, book: @book, played_on: Date.current)
    login_as @student

    get library_book_path(@book)
    assert_response :success
    assert_select "[data-game-completion]", 0
    assert_match "아직 이 책으로 한 활동이 없어요", response.body
  end

  test "기록이 없는 책은 빈 안내와 활동하기 링크를 보인다" do
    login_as @student
    get library_book_path(@book)
    assert_response :success
    assert_match "아직 이 책으로 한 활동이 없어요", response.body
    assert_select "#book-reports", 0
    assert_select "a[href=?]", reading_activity_path(book_id: @book.id)
  end

  test "없는 책은 404, 학생이 아니면 홈으로 보낸다" do
    login_as @student
    get library_book_path(id: 0)
    assert_response :not_found

    delete session_path
    login_as @teacher
    get library_book_path(@book)
    assert_redirected_to root_path
  end

  private

  def sequel(user, body, **attributes)
    BookSequel.create!({ user: user, book: @book, classroom: user.classroom, body: body }.merge(attributes))
  end

  def contribution(user, prompt)
    QuizContribution.create!(user: user, book: @book, classroom: user.classroom, content_axis: :mcq, band: :g34,
                             payload: { "prompt" => prompt, "choices" => %w[가 나 다 라], "answer_index" => 0, "explanation" => "" })
  end
end
