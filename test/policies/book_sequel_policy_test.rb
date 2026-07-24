require "test_helper"

# 뒷이야기 이어쓰기 정책(BookIntroPolicy 미러). 경계=학급: 작성은 학급 소속 학생, 공감은 같은 학급
# 또래의 글만(자기 글 제외), 회수는 본인 학급 내, Scope 는 본인 학급만. 크로스-학급 차단을 검증한다.
class BookSequelPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "뒷이야기정책초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @teacher = User.create!(school: @school, classroom: @room_a, name: "정책교사", role: :teacher, password: "password")
    @author = User.create!(school: @school, classroom: @room_a, name: "정책작가", password: "password")
    @peer = User.create!(school: @school, classroom: @room_a, name: "정책또래", password: "password")
    @outsider = User.create!(school: @school, classroom: @room_b, name: "타학급학생", password: "password")
    @book = Book.create!(title: "정책책", category: :recommended)
    @sequel = BookSequel.create!(user: @author, book: @book, classroom: @room_a, body: "정책 검증용 뒷이야기입니다.")
  end

  test "a classroom student may create; a non-student or classless user may not" do
    assert BookSequelPolicy.new(@author, BookSequel.new).create?
    assert_not BookSequelPolicy.new(@teacher, BookSequel.new).create?
    assert_not BookSequelPolicy.new(nil, BookSequel.new).create?
  end

  test "a same-classroom peer may cheer another student's sequel" do
    assert BookSequelPolicy.new(@peer, @sequel).vote?
  end

  test "a student cannot cheer their own sequel" do
    assert_not BookSequelPolicy.new(@author, @sequel).vote?
  end

  test "a cross-classroom student cannot cheer" do
    assert_not BookSequelPolicy.new(@outsider, @sequel).vote?
  end

  test "unvote is allowed for a same-classroom student and blocked cross-classroom" do
    assert BookSequelPolicy.new(@peer, @sequel).unvote?
    assert_not BookSequelPolicy.new(@outsider, @sequel).unvote?
  end

  test "Scope returns only the viewer's own classroom sequels" do
    other = BookSequel.create!(user: @outsider, book: @book, classroom: @room_b, body: "타 학급 뒷이야기입니다.")

    scoped = BookSequelPolicy::Scope.new(@peer, BookSequel).resolve.pluck(:id)
    assert_includes scoped, @sequel.id
    assert_not_includes scoped, other.id
  end

  test "Scope is empty for a classless user" do
    classless = User.create!(school: @school, name: "무학급교직원", role: :teacher,
                             email: "classless@test.local", password: "password")
    assert_empty BookSequelPolicy::Scope.new(classless, BookSequel).resolve
  end
end
