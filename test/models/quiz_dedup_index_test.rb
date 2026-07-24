require "test_helper"

# Phase 2b §2b.4 (A2) — 콘텐츠축 dedup 권위 = 부분 유니크 인덱스.
#   (book_id, band, content_axis, content_version) WHERE origin = <정수 1> 이 유일.
# 술어는 반드시 정수 enum 값(문자열 'system'은 정수 컬럼과 0행 매칭 → dedup 무효).
# teacher 행(origin=0)은 부분 술어에서 제외되어 자유롭게 중복될 수 있다.
class QuizDedupIndexTest < ActiveSupport::TestCase
  INDEX_NAME = "index_quizzes_on_content_axis_dedup".freeze

  setup do
    @school = School.create!(name: "덤프초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "덤프교사", password: "password", role: :teacher)
    @book = Book.create!(title: "덤프책", category: :recommended)
  end

  def system_quiz(content_version: 1, content_axis: :mcq)
    Quiz.create!(title: "system #{SecureRandom.hex(3)}", created_by: @teacher, book: @book, scope: :global,
                 published: true, origin: :system, content_axis: content_axis, band: :g56,
                 content_version: content_version)
  end

  test "duplicate system rows on the same (book, band, axis, version) raise RecordNotUnique" do
    system_quiz(content_version: 1)
    assert_raises(ActiveRecord::RecordNotUnique) { system_quiz(content_version: 1) }
  end

  test "different content_version on the same axis is allowed (re-roll)" do
    system_quiz(content_version: 1)
    assert_nothing_raised { system_quiz(content_version: 2) }
  end

  test "different content_axis on the same version is allowed" do
    system_quiz(content_version: 1, content_axis: :mcq)
    assert_nothing_raised { system_quiz(content_version: 1, content_axis: :matching) }
  end

  # teacher 행은 부분 술어(origin=1)에서 제외 → 같은 키로 중복 가능(교사 퀴즈는 dedup 대상 아님).
  test "teacher rows are excluded from the partial predicate and may duplicate" do
    2.times do
      Quiz.create!(title: "teacher #{SecureRandom.hex(3)}", created_by: @teacher, book: @book, scope: :global,
                   published: true, origin: :teacher, content_axis: :mcq, band: :g56, content_version: 1)
    end
    assert_equal 2, Quiz.where(origin: :teacher, book_id: @book.id, content_axis: :mcq, band: :g56).count
  end

  # A2 핵심: 부분 인덱스 술어의 정수값이 Quiz.origins[:system] 과 정확히 일치해야 dedup 이 실작동한다.
  test "the partial index predicate uses the integer Quiz.origins[:system], not a string" do
    assert_equal 1, Quiz.origins[:system], "system enum 정수 매핑이 1 이 아니면 술어를 재확인해야 한다"

    index = ActiveRecord::Base.connection.indexes("quizzes").find { |i| i.name == INDEX_NAME }
    assert_not_nil index, "부분 유니크 인덱스가 존재해야 한다"
    assert index.unique, "인덱스는 unique 여야 한다"
    assert_equal "origin = #{Quiz.origins[:system]}", index.where, "술어는 정수 origin=1(문자열 'system' 금지)"
  end
end
