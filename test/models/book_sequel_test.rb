require "test_helper"

# 뒷이야기 이어쓰기 글(게임 재구성 Phase 2의 창작 소셜 도메인, BookIntro 미러 + AI 코멘트).
# body 검증(길이·presence)·ai_status enum·랭킹/학급 스코프·공감 1인 1표를 검증한다.
# AI 코멘트의 담임 승인 게이트(comment_visible?·approve·awaiting_review, 2026-09-19)도 여기서 고정한다.
class BookSequelTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "뒷이야기초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @author = User.create!(school: @school, classroom: @room_a, name: "이야기작가", password: "password")
    @peer = User.create!(school: @school, classroom: @room_a, name: "같은반친구", password: "password")
    @book = Book.create!(title: "뒷이야기책", author: "지은이", category: :recommended)
    @teacher = User.create!(school: @school, name: "담임", role: :teacher, email: "sequel-teacher@example.com", password: "password")
  end

  def build_sequel(attrs = {})
    BookSequel.new({ user: @author, book: @book, classroom: @room_a,
                     body: "책이 끝난 뒤 주인공은 새로운 모험을 떠났어요." }.merge(attrs))
  end

  test "is valid with a body of at least 10 characters" do
    assert build_sequel.valid?
  end

  test "rejects a blank or too-short body" do
    assert_not build_sequel(body: "").valid?
    assert_not build_sequel(body: "짧음").valid?
  end

  test "rejects a body longer than 2000 characters (longer than intro since it is a story)" do
    assert build_sequel(body: "가" * 2000).valid?
    assert_not build_sequel(body: "가" * 2001).valid?
  end

  test "ai_status defaults to pending and mirrors the Report enum mapping" do
    assert BookSequel.create!(build_sequel.attributes.except("id")).pending?
    assert_equal({ "pending" => 0, "processing" => 1, "done" => 2, "failed" => 3 }, BookSequel.ai_statuses)
  end

  test "ranked orders by votes_count desc then created_at desc" do
    low = BookSequel.create!(user: @author, book: @book, classroom: @room_a, body: "첫 번째 뒷이야기입니다.")
    high = BookSequel.create!(user: @peer, book: @book, classroom: @room_a, body: "두 번째 뒷이야기입니다.")
    high.update!(votes_count: 5)

    assert_equal [ high.id, low.id ], BookSequel.ranked.pluck(:id)
  end

  test "for_classroom scopes to the given book and classroom" do
    mine = BookSequel.create!(user: @author, book: @book, classroom: @room_a, body: "우리 반 이야기입니다.")
    other_room = BookSequel.create!(user: @author, book: @book, classroom: @room_b, body: "다른 반 이야기입니다.")

    ids = BookSequel.for_classroom(@book, @room_a).pluck(:id)
    assert_includes ids, mine.id
    assert_not_includes ids, other_room.id
  end

  test "a peer can cheer once but a duplicate cheer is rejected (one vote per sequel)" do
    sequel = BookSequel.create!(user: @author, book: @book, classroom: @room_a, body: "공감을 받을 이야기입니다.")
    assert BookSequelVote.create(book_sequel: sequel, user: @peer).persisted?
    assert_not BookSequelVote.new(book_sequel: sequel, user: @peer).valid?
    assert_equal 1, sequel.reload.votes_count
  end

  test "voted_by? reflects whether a user has cheered" do
    sequel = BookSequel.create!(user: @author, book: @book, classroom: @room_a, body: "공감 여부 확인 이야기입니다.")
    assert_not sequel.voted_by?(@peer)
    BookSequelVote.create!(book_sequel: sequel, user: @peer)
    assert sequel.reload.voted_by?(@peer)
  end

  # ── AI 코멘트 담임 승인 게이트 ─────────────────────────────────────────────
  test "an AI comment is not visible until a teacher approves it" do
    sequel = BookSequel.create!(build_sequel.attributes.except("id").merge(ai_status: :done, ai_comment: "멋진 상상이에요!"))
    assert_not sequel.comment_visible?, "AI 코멘트가 있어도 승인 전에는 학생에게 보이지 않는다"

    assert sequel.approve(by: @teacher, comment: "멋진 상상이에요!")
    assert sequel.reload.comment_visible?
    assert_equal "멋진 상상이에요!", sequel.final_comment
    assert_equal @teacher, sequel.reviewed_by
  end

  test "approving an unchanged comment keeps teacher_comment empty; an edited one stores it beside the AI original" do
    sequel = BookSequel.create!(build_sequel.attributes.except("id").merge(ai_status: :done, ai_comment: "AI가 쓴 코멘트예요."))

    assert sequel.approve(by: @teacher, comment: " AI가 쓴 코멘트예요.\r\n")
    assert_nil sequel.reload.teacher_comment, "줄바꿈·앞뒤 공백만 다르면 고치지 않은 것으로 본다"

    first_approved_at = sequel.reviewed_at
    travel 1.hour do
      assert sequel.approve(by: @teacher, comment: "선생님이 고친\r\n코멘트예요.")
    end
    sequel.reload
    assert_equal "선생님이 고친\n코멘트예요.", sequel.teacher_comment
    assert_equal "선생님이 고친\n코멘트예요.", sequel.final_comment
    assert_equal "AI가 쓴 코멘트예요.", sequel.ai_comment, "AI 원문은 보존한다"
    assert_equal first_approved_at, sequel.reviewed_at, "다시 고쳐도 처음 승인 시각은 그대로다"
  end

  test "re-editing keeps the first approving teacher" do
    sequel = BookSequel.create!(build_sequel.attributes.except("id").merge(ai_status: :done, ai_comment: "코멘트"))
    other = User.create!(school: @school, name: "다른교사", role: :teacher, password: "password")
    assert sequel.approve(by: @teacher, comment: "코멘트")
    assert sequel.approve(by: other, comment: "다시 고친 코멘트")
    assert_equal @teacher, sequel.reload.reviewed_by
  end

  test "a comment longer than the limit is rejected" do
    sequel = BookSequel.create!(build_sequel.attributes.except("id").merge(ai_status: :done, ai_comment: "코멘트"))
    assert_not sequel.approve(by: @teacher, comment: "가" * (BookSequel::COMMENT_MAX_LENGTH + 1))
    assert_includes sequel.errors.full_messages.to_sentence, "#{BookSequel::COMMENT_MAX_LENGTH}자까지"
    assert_not sequel.reload.reviewed?
    assert sequel.approve(by: @teacher, comment: "가" * BookSequel::COMMENT_MAX_LENGTH)
  end

  test "a blank comment cannot be approved" do
    sequel = BookSequel.create!(build_sequel.attributes.except("id").merge(ai_status: :failed))
    assert_not sequel.approve(by: @teacher, comment: "  ")
    assert_includes sequel.errors.full_messages.to_sentence, "코멘트가 비어 있어요"
    assert_not sequel.reload.reviewed?
  end

  test "awaiting_review lists finished, unapproved sequels only" do
    base = build_sequel.attributes.except("id")
    done = BookSequel.create!(base.merge(ai_status: :done, ai_comment: "코멘트"))
    failed = BookSequel.create!(base.merge(ai_status: :failed))
    working = BookSequel.create!(base.merge(ai_status: :processing))
    approved = BookSequel.create!(base.merge(ai_status: :done, ai_comment: "코멘트", reviewed_at: Time.current))

    ids = BookSequel.awaiting_review.pluck(:id)
    assert_includes ids, done.id
    assert_includes ids, failed.id
    assert_not_includes ids, working.id, "코멘트 잡이 도는 중인 글은 아직 검토할 수 없다"
    assert_not_includes ids, approved.id
    assert_equal [ approved.id ], BookSequel.reviewed.pluck(:id)
  end
end
