require "test_helper"

# P6.5 사서 이달의 책·행사 CRUD + 학교 경계.
class LibrarianEventsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "행사학교")
    @librarian = User.create!(school: @school, name: "행사사서", role: :librarian, password: "password")
  end

  test "index lists the school's events" do
    LibraryEvent.create!(school: @school, title: "봄 독서주간")
    login_as @librarian
    get librarian_events_path
    assert_response :success
    assert_match "봄 독서주간", response.body
  end

  test "create adds an event scoped to the librarian's school" do
    login_as @librarian
    assert_difference -> { LibraryEvent.count }, 1 do
      post librarian_events_path, params: { library_event: { title: "여름 책잔치", description: "설명", event_on: "2026-08-01" } }
    end
    created = LibraryEvent.find_by(title: "여름 책잔치")
    assert_equal @school.id, created.school_id
  end

  test "update edits an event" do
    event = LibraryEvent.create!(school: @school, title: "원래제목")
    login_as @librarian
    patch librarian_event_path(event), params: { library_event: { title: "바뀐제목" } }
    assert_equal "바뀐제목", event.reload.title
  end

  test "destroy removes an event" do
    event = LibraryEvent.create!(school: @school, title: "삭제행사")
    login_as @librarian
    assert_difference -> { LibraryEvent.count }, -1 do
      delete librarian_event_path(event)
    end
  end

  test "cannot access another school's event (boundary → 404)" do
    other_school = School.create!(name: "남의행사학교")
    other_event = LibraryEvent.create!(school: other_school, title: "남의행사")
    login_as @librarian
    get librarian_event_path(other_event)
    assert_response :not_found
  end

  test "a teacher is forbidden from librarian events" do
    classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    teacher = User.create!(school: @school, classroom: classroom, name: "행사교사", role: :teacher, password: "password", approved: true)
    login_as teacher
    get librarian_events_path
    assert_response :forbidden
  end

  private
end
