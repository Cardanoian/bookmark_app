require "test_helper"
require Rails.root.join("db/migrate/20260720000000_hard_delete_vocab_game.rb")

# 게임 재구성 Phase 1 — vocab hard-delete 마이그레이션(계획서 §6) 동작 검증.
#   up : game_plays(game_type=2, vocab) 전량 + content_axis=1(matching) 퀴즈와 자식
#        (question/attempt/report) 전량 삭제. 정수 리터럴을 쓰므로 모델 enum 에서 vocab 이
#        빠진 뒤에도(=현재) 잔존 정수 2 행을 유령 없이 지운다.
#   down: IrreversibleMigration.
# DML 전용(스키마 변경 없음)이라 트랜잭션 테스트 안에서 안전하게 롤백된다.
class HardDeleteVocabGameTest < ActiveSupport::TestCase
  setup do
    @migration = HardDeleteVocabGame.new
    @migration.verbose = false

    @school = School.create!(name: "삭제초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "삭제학생", password: "password")
    @author = User.create!(name: "삭제시스템", role: :superadmin, password: "password")
    @book = Book.create!(title: "삭제책", category: :recommended)

    # matching(content_axis=1) 퀴즈 + 자식들 — 전량 삭제 대상.
    @matching_quiz = Quiz.create!(title: "matching 퀴즈", created_by: @author, book: @book, scope: :global,
                                  published: true, origin: :system, content_axis: :matching, band: :g56,
                                  content_version: 1, generation_status: :ready)
    @matching_question = @matching_quiz.quiz_questions.create!(question_type: :matching, position: 1,
                                                              content: { lefts: %w[가 나], rights: %w[A B] },
                                                              answer: { "0" => "1" })
    @matching_attempt = @matching_quiz.quiz_attempts.create!(user: @student, score: 0, points_awarded: 0, played_at: Time.current)
    @matching_report = @matching_quiz.quiz_reports.create!(user: @student)

    # mcq(content_axis=0) 퀴즈 + 문항 — 보존 대상.
    @mcq_quiz = Quiz.create!(title: "mcq 퀴즈", created_by: @author, book: @book, scope: :global,
                             published: true, origin: :system, content_axis: :mcq, band: :g56,
                             content_version: 1, generation_status: :ready)
    @mcq_question = @mcq_quiz.quiz_questions.create!(question_type: :mcq_single, choices: %w[가 나 다 라],
                                                     answer_index: 0, position: 1)

    # game_plays: quiz(0) 보존 + vocab(2) 삭제 대상. vocab 은 enum 에서 빠져 raw SQL 로 삽입한다.
    @surviving_play = @student.game_plays.create!(game_type: :quiz, book: @book, played_on: Date.current)
    insert_vocab_game_play!
  end

  test "up deletes vocab game_plays and matching quizzes with children, preserving the rest" do
    assert_equal 1, vocab_game_play_count, "사전: raw 삽입한 vocab(2) game_play 1건"

    @migration.up

    # 삭제 확인
    assert_equal 0, vocab_game_play_count, "vocab(2) game_plays 전량 삭제"
    assert_not Quiz.exists?(@matching_quiz.id), "matching 퀴즈 삭제"
    assert_not QuizQuestion.exists?(@matching_question.id), "matching 퀴즈 문항 삭제"
    assert_not QuizAttempt.exists?(@matching_attempt.id), "matching 퀴즈 attempt 삭제"
    assert_not QuizReport.exists?(@matching_report.id), "matching 퀴즈 report 삭제"

    # 보존 확인(무관 데이터는 그대로)
    assert Quiz.exists?(@mcq_quiz.id), "mcq 퀴즈는 보존"
    assert QuizQuestion.exists?(@mcq_question.id), "mcq 문항은 보존"
    assert GamePlay.exists?(@surviving_play.id), "quiz(0) game_play 는 보존"
  end

  test "down raises IrreversibleMigration" do
    assert_raises(ActiveRecord::IrreversibleMigration) { @migration.down }
  end

  private

  def insert_vocab_game_play!
    now = Time.current.utc.strftime("%Y-%m-%d %H:%M:%S")
    ActiveRecord::Base.connection.execute(
      "INSERT INTO game_plays (user_id, game_type, played_on, created_at, updated_at) " \
      "VALUES (#{@student.id}, 2, '#{Date.current}', '#{now}', '#{now}')"
    )
  end

  def vocab_game_play_count
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM game_plays WHERE game_type = 2").to_i
  end
end
