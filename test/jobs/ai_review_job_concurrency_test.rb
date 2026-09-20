require "test_helper"

# 첨삭 결과 확정·승인의 **병렬·롤백** 검증(BUG_FIX_PLAN F2 §4.3 · F3 §5.2 · §6). 서로 다른 DB 연결에서 같은 버전의
# 작업이 동시에 끝나거나, 승인과 재제출이 겹쳐도 결과·보상·승인 전이가 한 번인지 본다. 스레드가 서로의 커밋을
# 봐야 하고, 트랜잭션 롤백도 실제로 일어나야 하므로(픽스처 트랜잭션 안에서는 안쪽 transaction 이 바깥에 합류해
# 롤백되지 않는다) 트랜잭션 픽스처를 끈다(mission_reward_concurrency_test 선례).
class AiReviewJobConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  class HighReview
    def call(_report)
      { rubric: { content: 5, emotion: 5, life: 5, structure: 5, spelling: 5 }, praise: [], fix: [], grow: [] }
    end
  end

  setup do
    @school = School.create!(name: "첨삭동시초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "첨삭동시생", password: "password", points: 0)
    @report = Report.create!(user: @student, classroom: @classroom, book_title: "동시책",
                             body: "나는 이 책을 읽고 우리의 삶을 생각했다. 감동을 느꼈다.")
    @report.record_submission!
  end

  teardown do
    Report.where(classroom_id: @classroom&.id).delete_all
    SeasonScore.where(user_id: @student&.id).delete_all
    UserBadge.where(user_id: @student&.id).delete_all
    User.where(school_id: @school&.id).delete_all
    Classroom.where(school_id: @school&.id).delete_all
    School.where(id: @school&.id).delete_all
  end

  test "같은 버전의 작업이 두 연결에서 동시에 끝나도 결과 확정과 적립은 한 번이다" do
    stub_review(HighReview.new) do
      in_parallel(3) { AiReviewJob.perform_now(Report.find(@report.id), expected_review_version: 1) }
    end

    @report.reload
    assert @report.review_ready?
    assert_equal 30, @report.points_awarded
    assert_equal 30, @student.reload.points, "겹쳐 돈 작업이 저마다 적립하지 않는다"
    assert_equal 30, @student.experience
    assert_equal 30, SeasonScore.where(user_id: @student.id).sum(:points_earned)
  end

  # 결과 저장과 지급(포인트·경험치·시즌 점수)은 한 트랜잭션이다 — 지급 도중 예외가 나면 결과도 함께 되돌린다.
  test "시즌 점수 갱신 중 예외가 나면 결과와 지급이 함께 롤백되고 같은 버전 재실행으로 복구된다" do
    User.define_method(:increment_season_score!) { |**| raise "season boom" } # 포인트를 올린 직후에 터진다
    begin
      stub_review(HighReview.new) { AiReviewJob.perform_now(Report.find(@report.id), expected_review_version: 1) }
    ensure
      User.send(:remove_method, :increment_season_score!) # Pointable 의 원래 메서드로 돌아간다
    end

    @report.reload
    assert @report.failed?
    assert_nil @report.completed_review_version, "확정이 롤백됐다"
    assert_nil @report.rubric, "결과 저장도 롤백됐다"
    assert_equal 0, @report.points_awarded
    assert_equal [ 0, 0 ], @student.reload.values_at(:points, :experience), "먼저 올린 포인트·경험치도 롤백됐다"
    assert @report.review_retryable?

    stub_review(HighReview.new) { AiReviewJob.perform_now(Report.find(@report.id), expected_review_version: 1) }

    assert @report.reload.review_ready?
    assert_equal 1, @report.review_version, "버전을 올리지 않고 복구한다"
    assert_equal 30, @student.reload.points
    assert_equal 30, SeasonScore.where(user_id: @student.id).sum(:points_earned)
  end

  test "같은 버전을 두 연결에서 동시에 승인해도 승인 전이는 한 번이다" do
    stub_review(HighReview.new) { AiReviewJob.perform_now(Report.find(@report.id), expected_review_version: 1) }

    outcomes = in_parallel(3) { Report.find(@report.id).approve!(seen_version: 1) }

    assert_equal 1, outcomes.count(:approved), "후속 처리(보상·방송)를 일으키는 승인은 한 번뿐이다"
    assert_equal 2, outcomes.count(:already)
    assert @report.reload.reviewed?
  end

  test "승인과 재제출이 겹쳐도 새 제출이 승인된 채 남지 않는다" do
    stub_review(HighReview.new) { AiReviewJob.perform_now(Report.find(@report.id), expected_review_version: 1) }

    10.times do |round|
      seen = @report.reload.review_version
      results = in_parallel(2) do |i|
        i.zero? ? Report.find(@report.id).approve!(seen_version: seen) : Report.find(@report.id).record_submission!
      end

      @report.reload
      assert_equal seen + 1, @report.review_version
      assert_not @report.reviewed?, "새 제출은 미승인이다(#{round + 1}회차, 승인 결과 #{results.first})"
      assert_not @report.feedback_visible?
      assert_includes %i[approved stale], results.first

      # 다음 회차를 위해 새 버전의 첨삭을 끝낸다.
      stub_review(HighReview.new) { AiReviewJob.perform_now(Report.find(@report.id), expected_review_version: seen + 1) }
    end
  end

  private

  # Ai::ReviewService.new 를 대역으로 바꾼다(모든 스레드에 적용 — 클래스 단위).
  def stub_review(replacement)
    Ai::ReviewService.define_singleton_method(:new) { |*, **| replacement }
    yield
  ensure
    Ai::ReviewService.singleton_class.send(:remove_method, :new)
  end

  # 블록을 n 개의 스레드(각자 DB 연결)에서 동시에 시작한다. 예외는 모든 스레드가 끝난 뒤에 다시 올린다.
  def in_parallel(count)
    gate = Queue.new
    threads = count.times.map do |i|
      Thread.new do
        Thread.current.report_on_exception = false
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          yield i
        end
      rescue StandardError => e
        e
      end
    end
    count.times { gate << :go }
    results = threads.map(&:value)
    failure = results.find { |result| result.is_a?(StandardError) }
    raise failure if failure

    results
  end
end
