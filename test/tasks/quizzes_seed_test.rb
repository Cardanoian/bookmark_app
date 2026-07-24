require "test_helper"
require "rake"

# #9-seed: 샘플 퀴즈 시드(quizzes:seed)가 Phase 1 신규 컬럼(origin/content_axis/band/
# content_version + 문항 question_type/source)을 반영하고 멱등 재현되는지 검증한다.
class QuizzesSeedTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("quizzes:seed")
    @superadmin = User.create!(name: "시드총괄", role: :superadmin, password: "password")
    @book = Book.create!(title: "마당을 나온 암탉", category: :recommended)
  end

  def run_seed!
    Rake::Task["quizzes:seed"].reenable
    capture_io { Rake::Task["quizzes:seed"].invoke }
  end

  test "seeds the sample quiz with Phase 1 content-axis metadata" do
    run_seed!

    quiz = Quiz.find_by(title: "#{@book.title} 독서 퀴즈")
    assert_not_nil quiz, "샘플 퀴즈가 시드돼야 한다"
    assert_equal "teacher", quiz.origin
    assert_equal "mcq", quiz.content_axis
    assert_equal "g56", quiz.band, "전역(학급 없음) → g56 폴백"
    assert_equal 1, quiz.content_version
    assert quiz.published?
  end

  test "seeds questions as mcq_single/manual" do
    run_seed!
    quiz = Quiz.find_by(title: "#{@book.title} 독서 퀴즈")
    assert_operator quiz.quiz_questions.count, :>, 0
    quiz.quiz_questions.each do |q|
      assert_equal "mcq_single", q.question_type
      assert_equal "manual", q.source
    end
  end

  test "seeding is idempotent (find_or_initialize by title)" do
    run_seed!
    run_seed!
    assert_equal 1, Quiz.where(title: "#{@book.title} 독서 퀴즈").count
  end
end
