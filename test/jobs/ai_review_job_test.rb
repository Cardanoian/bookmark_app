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

  class HighReview
    def call(_report)
      { rubric: { content: 5, emotion: 5, life: 5, structure: 5, spelling: 5 }, praise: [], fix: [], grow: [] }
    end
  end

  class LowReview
    def call(_report)
      { rubric: { content: 1, emotion: 1, life: 1, structure: 1, spelling: 1 }, praise: [], fix: [], grow: [] }
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

  test "re-review awards only the delta, not full points again (idempotent, anti-farming)" do
    AiReviewJob.perform_now(@report)
    first_award = @user.reload.points
    awarded = @report.reload.points_awarded
    assert_operator awarded, :>, 0
    assert_equal awarded, first_award

    # 재첨삭(동일 본문 재평가) — 등급이 같으면 차액 0, 포인트 재지급 없음.
    AiReviewJob.perform_now(@report)
    assert_equal first_award, @user.reload.points, "재첨삭이 포인트를 이중 지급하면 안 된다"
  end

  # #misc: 재첨삭 등급 하락(음수 델타)은 잔액을 차감하되 진화를 되돌리지 않는다(단조).
  # check_evolution! 은 음수 델타에서 의도적으로 스킵된다(순수 술어·역진화 없음).
  test "a negative delta decrements points but never de-evolves the active monster (monotonic)" do
    seed_monster_species!

    stub_new(Ai::ReviewService, HighReview.new) { AiReviewJob.perform_now(@report) }
    high_points = @user.reload.points
    assert_operator high_points, :>, 0

    # 스타터를 2단계로 올려 둔다(단조성 확인용 세팅).
    MonsterAcquisition.new(@user).choose_starter!("pup_1")
    stage2 = MonsterSpecies.find_by!(key: "pup_2")
    @user.active_monster.update!(monster_species: stage2, dex_no: stage2.dex_no)

    stub_new(Ai::ReviewService, LowReview.new) { AiReviewJob.perform_now(@report) }

    assert_operator @user.reload.points, :<, high_points, "음수 델타는 잔액을 차감한다"
    assert_equal stage2.id, @user.active_monster.monster_species_id, "포인트 하락이 진화를 되돌리지 않는다"
  end

  test "review points go through award_points so the ranking hook fires (not raw increment)" do
    # award_points 는 학생의 학급 랭킹 행을 실시간 갱신한다. increment! 였다면 방송이 없다.
    assert_turbo_stream_broadcasts([ @classroom, :ranking ]) do
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
