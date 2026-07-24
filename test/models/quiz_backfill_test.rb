require "test_helper"
require Rails.root.join("db/migrate/20260712000003_backfill_quiz_content_axis.rb")

# Phase 1 §1.4 — 기존 데이터 백필 마이그레이션 up/down 왕복 무손실.
#   up : content_axis 미상(NULL) 퀴즈 → origin=teacher / content_axis=mcq /
#        band=학급 학년 유도(미상 g56) / content_version=1, 문항 → mcq_single / manual.
#   down: 백필로 유도한 content_axis·band 만 NULL 로 되돌린다.
class QuizBackfillTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "백필초")
    @g34 = Classroom.create!(school: @school, grade: 3, class_no: 1) # → band g34
    @teacher = User.create!(school: @school, classroom: @g34, name: "백필교사", password: "password", role: :teacher)
    @book = Book.create!(title: "백필책", category: :recommended)
    @migration = BackfillQuizContentAxis.new
  end

  # content_axis 를 NULL 로 둔(백필 이전 상태를 흉내낸) 퀴즈를 만든다.
  def pre_backfill_quiz(classroom: nil)
    quiz = Quiz.create!(title: "백필 대상 #{SecureRandom.hex(3)}", created_by: @teacher, book: @book,
                        scope: classroom ? :classroom : :global, classroom: classroom,
                        content_axis: nil, band: nil)
    quiz.quiz_questions.create!(prompt: "문", choices: %w[가 나], answer_index: 0, position: 1)
    quiz
  end

  def run_up
    ActiveRecord::Migration.suppress_messages { @migration.up }
  end

  def run_down
    ActiveRecord::Migration.suppress_messages { @migration.down }
  end

  test "up backfills origin/content_axis/content_version and question type/source" do
    quiz = pre_backfill_quiz
    run_up
    quiz.reload

    assert_equal "teacher", quiz.origin
    assert_equal "mcq", quiz.content_axis
    assert_equal 1, quiz.content_version
    question = quiz.quiz_questions.first
    assert_equal "mcq_single", question.question_type
    assert_equal "manual", question.source
  end

  test "up derives band from the classroom grade (nil classroom falls back to g56)" do
    in_g34 = pre_backfill_quiz(classroom: @g34)
    no_class = pre_backfill_quiz(classroom: nil)
    run_up

    assert_equal "g34", in_g34.reload.band, "grade 3 → g34 (ReadingDomain.band_for)"
    assert_equal "g56", no_class.reload.band, "학급 미상 → g56 폴백"
  end

  test "up then down is a lossless round-trip for the derived content_axis/band" do
    quiz = pre_backfill_quiz(classroom: @g34)

    run_up
    assert_equal "mcq", quiz.reload.content_axis
    assert_equal "g34", quiz.band

    run_down
    quiz.reload
    assert_nil quiz.content_axis, "down 은 유도한 content_axis 를 NULL 로 되돌린다"
    assert_nil quiz.band, "down 은 유도한 band 를 NULL 로 되돌린다"
  end
end
