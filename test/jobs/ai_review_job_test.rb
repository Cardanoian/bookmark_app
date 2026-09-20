require "test_helper"

class AiReviewJobTest < ActiveJob::TestCase
  setup do
    @school = School.create!(name: "리뷰잡학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "리뷰잡학생", password: "password")
    @user.update!(nickname: "리뷰별", ranking_opted_in: true)
    @report = Report.create!(
      user: @user, classroom: @classroom, book_title: "책",
      body: "나는 이 책을 읽고 우리의 삶을 생각했다. 감동을 느꼈다."
    )
    @report.record_submission! # 제출 버전 1 — 잡은 제출된 글의 현재 버전에만 결과를 반영한다.
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

  # 작업 순서를 sleep 없이 고정하는 대역. 첫 호출(이전 작업)이 첨삭을 만드는 도중에 블록을 실행해
  # 그사이 일어난 일(재제출·새 작업 완료)을 끼워 넣고, 그 뒤에 이전 작업의 결과를 돌려준다.
  class InterleavedReview
    def initialize(first:, later:, &during_first_call)
      @first = first
      @later = later
      @during_first_call = during_first_call
      @calls = 0
    end

    def call(report)
      @calls += 1
      return @later.call(report) unless @calls == 1

      @during_first_call.call
      @first.call(report)
    end
  end

  test "transitions pending to done and awards points (fallback, no network)" do
    assert @report.pending?
    points_before = @user.points

    perform_ai_review(@report)

    @report.reload
    assert @report.done?
    assert_not_nil @report.level
    assert_not_nil @report.avg
    assert_operator @user.reload.points, :>, points_before
  end

  test "passes through the processing state before completing" do
    recorder = StatusRecorder.new

    stub_new(Ai::ReviewService, recorder) do
      perform_ai_review(@report)
    end

    assert_equal "processing", recorder.status_during_call
    assert @report.reload.done?
  end

  test "marks the report failed and awards no points when review raises" do
    stub_new(Ai::ReviewService, RaisingReview.new) do
      assert_no_difference -> { @user.reload.points } do
        perform_ai_review(@report)
      end
    end

    assert @report.reload.failed?
  end

  test "computes improvement for a revision when prev_avg is present (P3.10)" do
    revision = Report.create!(
      user: @user, classroom: @classroom, book_title: "고쳐쓴 글",
      body: @report.body, revision_of: @report, prev_avg: 1.0
    )
    revision.record_submission!

    perform_ai_review(revision)

    revision.reload
    assert_not_nil revision.avg
    assert_in_delta revision.avg - 1.0, revision.improvement, 0.001
  end

  test "appends the completed report to the classroom review queue (P3.9)" do
    assert_turbo_stream_broadcasts([ @classroom, :review_queue ]) do
      perform_ai_review(@report)
    end
  end

  # 같은 버전은 한 번만 확정한다 — 같은 인자로 다시 돌아도(재시도·중복 적재) 다시 채점하거나 지급하지 않는다.
  test "re-running the same version neither re-scores nor pays again" do
    stub_new(Ai::ReviewService, LowReview.new) { perform_ai_review(@report) }
    assert_equal 10, @user.reload.points
    assert_equal 1, @report.reload.completed_review_version

    stub_new(Ai::ReviewService, HighReview.new) { perform_ai_review(@report) }

    @report.reload
    assert_equal "C", @report.level, "확정된 버전의 결과는 그대로다"
    assert_equal 10, @report.points_awarded
    assert_equal 10, @user.reload.points, "같은 버전의 재실행이 포인트를 이중 지급하면 안 된다"
  end

  # 정당한 재채점은 **새 제출 버전**에서 일어난다. 이미 지급한 것과의 차액만 반영한다(파밍 차단).
  test "a new submission version is re-scored and pays only the delta (up and down)" do
    stub_new(Ai::ReviewService, LowReview.new) { perform_ai_review(@report) }
    assert_reward_totals 10

    resubmit!(@report)
    stub_new(Ai::ReviewService, HighReview.new) { perform_ai_review(@report) }
    assert_equal [ 2, 2, "A", 30 ], @report.reload.values_at(:review_version, :completed_review_version, :level, :points_awarded)
    assert_reward_totals 30 # 등급 상승 — 차액 20 만 더 지급

    resubmit!(@report)
    stub_new(Ai::ReviewService, LowReview.new) { perform_ai_review(@report) }
    assert_equal [ 3, 3, "C", 10 ], @report.reload.values_at(:review_version, :completed_review_version, :level, :points_awarded)
    assert_reward_totals 10 # 등급 하락 — 지급 기록·포인트·경험치·시즌 점수를 함께 정정
  end

  # #misc: 재첨삭 등급 하락(음수 델타)은 잔액을 차감하되 진화를 되돌리지 않는다(단조).
  # check_evolution! 은 음수 델타에서 의도적으로 스킵된다(순수 술어·역진화 없음).
  test "a negative delta decrements points but never de-evolves the active monster (monotonic)" do
    seed_monster_species!

    stub_new(Ai::ReviewService, HighReview.new) { perform_ai_review(@report) }
    high_points = @user.reload.points
    assert_operator high_points, :>, 0

    # 스타터를 2단계로 올려 둔다(단조성 확인용 세팅).
    MonsterAcquisition.new(@user).choose_starter!("pup_1")
    stage2 = MonsterSpecies.find_by!(key: "pup_2")
    @user.active_monster.update!(monster_species: stage2, dex_no: stage2.dex_no)

    resubmit!(@report) # 재채점은 새 제출 버전에서 일어난다
    stub_new(Ai::ReviewService, LowReview.new) { perform_ai_review(@report) }

    assert_operator @user.reload.points, :<, high_points, "음수 델타는 잔액을 차감한다"
    assert_equal stage2.id, @user.active_monster.monster_species_id, "포인트 하락이 진화를 되돌리지 않는다"
  end

  # F2(BUG_FIX_PLAN §4): 이전 작업이 첨삭을 만드는 사이 학생이 고쳐 다시 냈고, 새 작업이 먼저 끝났다.
  # 재현: 늦게 끝난 이전 작업이 새 본문에 이전 첨삭을 덮어쓰고, 시작할 때 읽어 둔 points_awarded(0)로
  # 차액을 계산해 전액을 또 적립했다(글의 지급 기록 10점, 사용자 적립 40점).
  test "이전 작업이 늦게 끝나도 최신 제출의 첨삭과 보상을 덮어쓰지 않는다 (F2)" do
    interleaved = InterleavedReview.new(first: LowReview.new, later: HighReview.new) do
      resubmitted = Report.find(@report.id)
      resubmitted.update!(body: "고쳐 쓴 새 본문이에요. 주인공처럼 나도 용기를 내 보고 싶었어요.")
      AiReviewJob.perform_now(resubmitted, expected_review_version: resubmitted.record_submission!)
    end

    stub_new(Ai::ReviewService, interleaved) { AiReviewJob.perform_now(@report, expected_review_version: 1) }

    @report.reload
    assert_equal 5, @report.rubric_scores[:content], "최신 제출의 첨삭이 남는다"
    assert_equal "A", @report.level
    assert @report.done?
    assert_equal [ 2, 2 ], [ @report.review_version, @report.completed_review_version ]
    assert_equal 30, @report.points_awarded, "지급 기록은 최신 첨삭의 보상"
    assert_reward_totals 30 # 이전 작업이 같은 글의 보상을 또 적립하지 않는다
  end

  # 이전 버전 작업은 시작조차 하지 않는다(외부 AI 호출 없음) — 결과·상태 불변.
  test "a job for an older version does nothing" do
    perform_ai_review(@report)
    resubmit!(@report)
    before = @report.reload.attributes

    recorder = StatusRecorder.new
    stub_new(Ai::ReviewService, recorder) { AiReviewJob.perform_now(@report, expected_review_version: 1) }

    assert_nil recorder.status_during_call, "이전 버전 작업은 첨삭을 만들지 않는다"
    assert_equal before, @report.reload.attributes
    assert @report.pending?, "최신 제출은 여전히 제 작업을 기다린다"
  end

  # 배포 전 형식(버전 없음)으로 큐에 남아 있던 작업은 기록만 남기고 끝낸다 — 현재 버전을 임의로 붙이지 않는다(§7.2).
  test "a legacy job without a version is skipped" do
    assert_no_difference -> { @user.reload.points } do
      AiReviewJob.perform_now(@report)
    end
    assert @report.reload.pending?
    assert_nil @report.completed_review_version
  end

  # 배포 전에 큐에 들어간 작업은 인자가 글 하나뿐인 직렬화 형식이다 — 새 perform 서명으로도 역직렬화되고, 건너뛴다.
  test "an old-format serialized job (report only) still deserializes and is skipped" do
    payload = AiReviewJob.new(@report).serialize
    assert_equal 1, payload["arguments"].size, "구형 형식: 인자는 글(GlobalID) 하나"

    assert_nothing_raised { ActiveJob::Base.execute(payload) }

    assert @report.reload.pending?
    assert_nil @report.completed_review_version
    assert_equal 0, @user.reload.points
  end

  test "a draft is never reviewed even if a job names its version" do
    draft = Report.create!(user: @user, classroom: @classroom, book_title: "초안", body: "아직 내지 않은 글이에요.")

    AiReviewJob.perform_now(draft, expected_review_version: 0)

    assert draft.reload.pending?
    assert_nil draft.rubric
    assert_equal 0, @user.reload.points
  end

  # 이전 버전 작업의 뒤늦은 실패는 최신 제출을 failed 로 만들지 않는다.
  test "a late failure of an older job leaves the latest submission alone" do
    failing_late = InterleavedReview.new(first: RaisingReview.new, later: HighReview.new) do
      resubmitted = Report.find(@report.id)
      AiReviewJob.perform_now(resubmitted, expected_review_version: resubmitted.record_submission!)
    end

    stub_new(Ai::ReviewService, failing_late) { AiReviewJob.perform_now(@report, expected_review_version: 1) }

    assert @report.reload.done?, "이전 작업이 실패해도 최신 성공 상태가 남는다"
    assert_equal "A", @report.level
    assert_reward_totals 30
  end

  # 같은 버전의 다른 작업이 이미 성공했고 교사가 승인까지 했다면, 중복 작업의 뒤늦은 실패는 무시한다.
  test "a late failure of a duplicate job keeps the completed and approved result" do
    failing_duplicate = InterleavedReview.new(first: RaisingReview.new, later: HighReview.new) do
      AiReviewJob.perform_now(Report.find(@report.id), expected_review_version: 1) # 같은 버전의 다른 작업이 먼저 끝났다
      assert_equal :approved, Report.find(@report.id).approve!(seen_version: 1)
    end

    stub_new(Ai::ReviewService, failing_duplicate) { AiReviewJob.perform_now(@report, expected_review_version: 1) }

    @report.reload
    assert @report.done?
    assert @report.reviewed?, "승인이 유지된다"
    assert @report.feedback_visible?
    assert_reward_totals 30
  end

  # 같은 버전이 겹쳐 돌면 먼저 확정한 쪽만 반영된다(늦은 쪽의 결과·보상은 버린다).
  test "overlapping jobs of the same version finalize exactly once" do
    overlapping = InterleavedReview.new(first: LowReview.new, later: HighReview.new) do
      AiReviewJob.perform_now(Report.find(@report.id), expected_review_version: 1)
    end

    stub_new(Ai::ReviewService, overlapping) { AiReviewJob.perform_now(@report, expected_review_version: 1) }

    assert_equal "A", @report.reload.level, "먼저 확정한 결과가 남는다"
    assert_equal 30, @report.points_awarded
    assert_reward_totals 30
  end

  # 현재 버전이 실패로 끝난 글은 같은 버전으로 다시 예약해 복구한다 — 버전은 오르지 않는다(§4.4).
  test "a failed current version recovers by re-running the same version" do
    stub_new(Ai::ReviewService, RaisingReview.new) { perform_ai_review(@report) }
    assert @report.reload.failed?
    assert_not @report.review_ready?
    assert @report.review_retryable?

    perform_ai_review(@report)
    perform_ai_review(@report) # 한 번 더 돌아도 한 번만 반영

    @report.reload
    assert_equal 1, @report.review_version, "버전을 올리지 않는다"
    assert @report.review_ready?
    assert_equal @report.points_awarded, @user.reload.points
  end

  # 채점에는 작업이 시작할 때 확보한 학급 가중치를 쓴다(첨삭을 만드는 사이 담임이 가중치를 바꿔도).
  test "scores with the rubric weights captured when the job started" do
    @classroom.update!(rubric_config: { "weights" => { "content" => 1, "emotion" => 0, "life" => 0, "structure" => 0, "spelling" => 0 } })
    uneven = Class.new do
      define_method(:call) do |report|
        report.classroom.class.where(id: report.classroom_id)
              .update_all(rubric_config: { "weights" => { "content" => 0, "emotion" => 0, "life" => 0, "structure" => 0, "spelling" => 1 } }.to_json)
        { rubric: { content: 5, emotion: 0, life: 0, structure: 0, spelling: 0 }, praise: [], fix: [], grow: [] }
      end
    end.new

    stub_new(Ai::ReviewService, uneven) { perform_ai_review(@report) }

    assert_in_delta 5.0, @report.reload.avg, 0.001, "시작할 때의 가중치(내용 100%)로 채점한다"
  end

  # 방송·후크는 커밋 뒤의 부수 효과다 — 실패해도 확정한 결과를 실패로 뒤집거나 보상을 다시 주지 않는다.
  test "a broadcast failure after the commit keeps the completed result" do
    # broadcast_append_to 는 Turbo 모듈에서 온 메서드라, Report 에 잠시 덮어썼다가 지우면 원래대로 돌아간다.
    Report.define_method(:broadcast_append_to) { |*, **| raise "cable down" }
    begin
      perform_ai_review(@report)
    ensure
      Report.send(:remove_method, :broadcast_append_to)
    end

    @report.reload
    assert @report.done?, "방송 예외로 done 을 failed 로 바꾸지 않는다"
    assert @report.review_ready?
    assert_equal @report.points_awarded, @user.reload.points
  end

  # 결과를 확정한 직후·방송 직전에 학생이 다시 냈다면 오래된 검토 행을 덧붙이지 않는다(방송 전에 최신 상태를 다시 본다).
  test "no review-queue row is appended when the student resubmitted right after finalize" do
    report_id = @report.id
    original = User.instance_method(:run_point_side_effects!) # Pointable 의 메서드 — 커밋 뒤, 방송 앞에 불린다.
    User.define_method(:run_point_side_effects!) do
      Report.find(report_id).record_submission!
      original.bind_call(self)
    end

    begin
      assert_no_turbo_stream_broadcasts([ @classroom, :review_queue ]) { perform_ai_review(@report) }
    ensure
      User.send(:remove_method, :run_point_side_effects!)
    end
    assert_equal 2, @report.reload.review_version
  end

  private

  # 학생이 고쳐 다시 냈다(새 제출 버전).
  def resubmit!(report)
    report.reload.record_submission!
  end

  # 포인트·경험치·시즌 점수가 함께 움직인다(결과와 같은 트랜잭션에서 반영).
  def assert_reward_totals(expected)
    @user.reload
    assert_equal expected, @user.points
    assert_equal expected, @user.experience
    season = SeasonScore.find_by(user: @user, academic_year: Classroom.current_academic_year)
    assert_equal expected, season&.experience_earned.to_i
    assert_equal expected, season&.points_earned.to_i
  end

  # Minitest 6 dropped minitest/mock; temporarily swap `.new` on a service class
  # to return an injected double, then restore the inherited Class#new.
  def stub_new(klass, replacement)
    klass.define_singleton_method(:new) { |*, **| replacement }
    yield
  ensure
    klass.singleton_class.send(:remove_method, :new)
  end
end
