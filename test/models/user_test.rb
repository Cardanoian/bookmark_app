require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "유저초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
  end

  test "role enum defines five roles" do
    assert_equal(
      { "student" => 0, "teacher" => 1, "school_admin" => 2, "librarian" => 3, "superadmin" => 4 },
      User.roles
    )
  end

  test "mode enum defines two modes" do
    assert_equal({ "normal" => 0, "easy" => 1 }, User.modes)
  end

  test "defaults to student role and normal mode" do
    user = User.new
    assert user.student?
    assert user.normal?
  end

  test "has_secure_password authenticates correct password" do
    user = build_user(password: "secret123")
    assert user.save
    assert user.authenticate("secret123")
    assert_not user.authenticate("wrong-password")
  end

  test "password is stored hashed, not plaintext" do
    user = build_user(password: "secret123")
    user.save!
    assert_not_equal "secret123", user.password_digest
    assert user.password_digest.present?
  end

  test "requires a name" do
    assert_not build_user(name: nil).valid?
  end

  test "name must be unique within the tuple identity" do
    build_user(name: "홍길동").save!
    duplicate = build_user(name: "홍길동")
    assert_not duplicate.valid?
  end

  test "allows the same name in a different classroom" do
    other = Classroom.create!(school: @school, grade: 3, class_no: 2)
    build_user(name: "김철수").save!
    assert build_user(name: "김철수", classroom: other).valid?
  end

  test "superadmin can be created without a school" do
    admin = User.new(name: "총괄관리자", role: :superadmin, password: "password")
    assert admin.valid?
    assert_nil admin.school_id
  end

  private

  def build_user(attrs = {})
    User.new({ school: @school, classroom: @classroom, name: "학생1", password: "password" }.merge(attrs))
  end
end
