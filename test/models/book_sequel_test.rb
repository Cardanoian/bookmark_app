require "test_helper"

# 뒷이야기 이어쓰기 글(게임 재구성 Phase 2의 창작 소셜 도메인, BookIntro 미러 + AI 코멘트).
# body 검증(길이·presence)·ai_status enum·랭킹/학급 스코프·공감 1인 1표를 검증한다.
class BookSequelTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "뒷이야기초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @author = User.create!(school: @school, classroom: @room_a, name: "이야기작가", password: "password")
    @peer = User.create!(school: @school, classroom: @room_a, name: "같은반친구", password: "password")
    @book = Book.create!(title: "뒷이야기책", author: "지은이", category: :recommended)
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
end
