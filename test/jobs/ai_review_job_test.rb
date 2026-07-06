require "test_helper"

class AiReviewJobTest < ActiveJob::TestCase
  setup do
    @school = School.create!(name: "리뷰잡학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "리뷰잡학생", password: "password")
    @report = Report.create!(
      user: @user, classroom: @classroom, book_title: "책",
      body: "나는 이 책을 읽고 우리의 삶을 생각했다. 감동을 느꼈다."
    )
  end

  class StatusRecorder
    attr_reader :status_during_call

    def call(report)
      @status_during_call = report.ai_status
      Ai::RuleBasedReview.new.call(body: report.body)
    end
  end

  class RaisingReview
    def call(_report)
      raise "boom"
    end
  end

  test "transitions pending to done, awards points, and sets similarity (fallback, no network)" do
    assert @report.pending?
    points_before = @user.points

    AiReviewJob.perform_now(@report)

    @report.reload
    assert @report.done?
    assert_not_nil @report.level
    assert_not_nil @report.avg
    assert_not_nil @report.similarity
    assert_operator @report.similarity, :>=, 0.0
    assert_operator @report.similarity, :<=, 1.0
    assert_operator @user.reload.points, :>, points_before
  end

  test "passes through the processing state before completing" do
    recorder = StatusRecorder.new

    stub_new(Ai::ReviewService, recorder) do
      AiReviewJob.perform_now(@report)
    end

    assert_equal "processing", recorder.status_during_call
    assert @report.reload.done?
  end

  test "marks the report failed and awards no points when review raises" do
    stub_new(Ai::ReviewService, RaisingReview.new) do
      assert_no_difference -> { @user.reload.points } do
        AiReviewJob.perform_now(@report)
      end
    end

    assert @report.reload.failed?
  end

  test "computes improvement for a revision when prev_avg is present (P3.10)" do
    revision = Report.create!(
      user: @user, classroom: @classroom, book_title: "고쳐쓴 글",
      body: @report.body, revision_of: @report, prev_avg: 1.0
    )

    AiReviewJob.perform_now(revision)

    revision.reload
    assert_not_nil revision.avg
    assert_in_delta revision.avg - 1.0, revision.improvement, 0.001
  end

  test "appends the completed report to the classroom review queue (P3.9)" do
    assert_turbo_stream_broadcasts([ @classroom, :review_queue ]) do
      AiReviewJob.perform_now(@report)
    end
  end

  private

  # Minitest 6 dropped minitest/mock; temporarily swap `.new` on a service class
  # to return an injected double, then restore the inherited Class#new.
  def stub_new(klass, replacement)
    klass.define_singleton_method(:new) { |*, **| replacement }
    yield
  ensure
    klass.singleton_class.send(:remove_method, :new)
  end
end
