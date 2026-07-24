require "test_helper"

# Phase 2b §2b.2 — 워밍 잡. 상태 전이(warming→ready/폐기), Moderator 게시 전 검증,
# 비차단 Turbo 방송, dedup 가드(동시 적재→1생성), 실패/거부→오프라인 유지.
class GenerateGameContentJobTest < ActiveJob::TestCase
  # content_set 이 반환할 세트를 지정하는 가짜 draft service(잡 팩토리로 주입).
  class FakeDraftService
    attr_reader :calls

    def initialize(set)
      @set = set
      @calls = 0
    end

    def content_set(*)
      @calls += 1
      @set
    end
  end

  # 무키(오프라인) 서비스용 로컬 스텁(다른 테스트 파일 내부 클래스 의존 제거).
  class UnconfiguredClient
    def configured? = false
    def generate(**) = nil
  end

  setup do
    @book = Book.create!(title: "워밍책", author: "김작가", summary: "잎싹의 자유를 향한 모험 이야기.", category: :recommended)
    @offline_service = Ai::QuizDraftService.new(client: UnconfiguredClient.new)
    seed_offline_v1(:mcq)
  end

  teardown { GenerateGameContentJob.reset_factories! }

  # ContentProvider 미스 경로가 만드는 오프라인 v1(ready) 을 흉내 낸다.
  def seed_offline_v1(axis)
    quiz = Quiz.new(title: "온디맨드 #{axis}", created_by: Games::ContentProvider.system_user, book: @book,
                    scope: :global, published: true, origin: :system, content_axis: axis, band: :g56,
                    content_version: 1, generation_status: :ready)
    Games::ContentProvider.build_questions(quiz, @offline_service.offline_set(@book, :g56, axis), source: :offline)
    quiz.save!
    quiz
  end

  def valid_mcq_set
    @offline_service.offline_set(@book, :g56, :mcq)
  end

  def inject_service(set)
    service = FakeDraftService.new(set)
    GenerateGameContentJob.draft_service_factory = -> { service }
    service
  end

  def system_mcq_rows
    Quiz.where(origin: :system, book_id: @book.id, content_axis: :mcq)
  end

  # ── 해피 패스: warming→ready, source=ai, moderator 통과 ─────────────────
  test "publishes a warmed AI version (warming -> ready, source ai) when the moderator passes" do
    inject_service(valid_mcq_set)

    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")

    v2 = system_mcq_rows.find_by(content_version: 2)
    assert_not_nil v2, "새 content_version 이 게시되어야 한다"
    assert_equal "ready", v2.generation_status
    assert_equal ReadingDomain::CONTENT_COUNTS[:mcq], v2.quiz_questions.count
    assert_equal [ "ai" ], v2.quiz_questions.pluck(:source).uniq
    assert_equal "ready", system_mcq_rows.find_by(content_version: 1).generation_status, "오프라인 v1 은 그대로 유지"
  end

  # ── Moderator 거부(금칙어) → 게시 안 함, 오프라인 유지 ───────────────────
  test "a denylisted set is rejected pre-publish and the offline set is kept (nothing published)" do
    bad = valid_mcq_set
    bad.first[:prompt] = "씨발 부적절한 문항"
    service = inject_service(bad)

    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")

    assert_equal 1, service.calls, "생성은 시도하되"
    assert_nil system_mcq_rows.find_by(content_version: 2), "거부분은 게시되지 않는다(warming 행 폐기)"
    assert_equal 1, system_mcq_rows.count, "오프라인 v1 만 남는다"
    assert_equal [ "offline" ], system_mcq_rows.first.quiz_questions.pluck(:source).uniq
  end

  # ── 구조 위반(count 부족) → 거부 → 오프라인 유지 ────────────────────────
  test "a structurally invalid set (wrong count) is rejected and offline is kept" do
    inject_service(valid_mcq_set.first(3)) # 5→3

    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")

    assert_nil system_mcq_rows.find_by(content_version: 2)
    assert_equal 1, system_mcq_rows.count
  end

  # ── dedup 가드: 두 번(동시) 적재 → 1생성 ────────────────────────────────
  test "dedup guard — a second enqueue after a fresh warm does not regenerate" do
    service = inject_service(valid_mcq_set)

    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq") # v2 ready
    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq") # 이미 v2 ready → redundant

    assert_equal 1, service.calls, "이미 워밍된 콘텐츠축은 재생성하지 않는다"
    assert_equal 1, system_mcq_rows.where("content_version >= 2").count
  end

  # 선점 경쟁 시뮬레이션: warming 행이 이미 있으면 두 번째 잡은 조기 반환.
  test "an in-progress warming row makes a concurrent job early-return" do
    Quiz.create!(title: "온디맨드 mcq v2", created_by: Games::ContentProvider.system_user, book: @book,
                 scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                 content_version: 2, generation_status: :warming)
    service = inject_service(valid_mcq_set)

    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")

    assert_equal 0, service.calls, "warming 진행 중이면 중복 생성하지 않는다"
  end

  # ── 비차단 Turbo 방송 ───────────────────────────────────────────────────
  test "broadcasts a non-blocking Turbo stream when a new version is published" do
    inject_service(valid_mcq_set)

    assert_turbo_stream_broadcasts([ @book.id, "g56", "mcq", :game_content ]) do
      GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")
    end
  end

  # ── 알 수 없는 책 → 무시(크래시 없음) ──────────────────────────────────
  test "an unknown book id is a no-op" do
    assert_nothing_raised { GenerateGameContentJob.new.perform(-1, "g56", "mcq") }
  end

  # ── §2b 검증 후속 [MEDIUM] 신고→재생성 침묵 no-op 봉인 ───────────────────
  # 신고된(reported=true) AI ready 행을 "이미 AI 워밍됨"으로 오판하면, 신고 후 재생성 잡이
  # 조기 반환해 해당 (book,band,axis)가 영구 오프라인에 갇힌다(침묵 no-op). 이제는 reported
  # 행을 제외하고, "AI 로 게시됨" 판정도 버전 크기가 아니라 실제 quiz_questions.source==ai 로 한다.
  test "a reported AI-ready row no longer blocks regeneration — perform actually republishes fresh AI content" do
    reported_ai_v2 = Quiz.new(title: "온디맨드 mcq v2", created_by: Games::ContentProvider.system_user, book: @book,
                              scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                              content_version: 2, generation_status: :ready, reported: true)
    Games::ContentProvider.build_questions(reported_ai_v2, valid_mcq_set, source: :ai)
    reported_ai_v2.save!

    service = inject_service(valid_mcq_set)
    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")

    v3 = system_mcq_rows.find_by(content_version: 3)
    assert_not_nil v3, "신고된 AI 행은 '이미 워밍됨'으로 치지 않아 새 버전이 실제로 생성·게시돼야 한다"
    assert_equal "ready", v3.generation_status
    assert_equal [ "ai" ], v3.quiz_questions.pluck(:source).uniq
    assert_equal 1, service.calls, "재생성이 실제로 시도됐다(침묵 no-op 아님)"
  end

  # 회귀 방지: 신고되지 않은 AI ready 행은 여전히 dedup 대상이어야 한다(기존 동작 보존).
  test "a non-reported AI-ready row still blocks regeneration (existing dedup preserved)" do
    ai_v2 = Quiz.new(title: "온디맨드 mcq v2", created_by: Games::ContentProvider.system_user, book: @book,
                     scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                     content_version: 2, generation_status: :ready, reported: false)
    Games::ContentProvider.build_questions(ai_v2, valid_mcq_set, source: :ai)
    ai_v2.save!

    service = inject_service(valid_mcq_set)
    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")

    assert_equal 0, service.calls, "이미 게시된 AI 콘텐츠는 재생성하지 않는다"
    assert_nil system_mcq_rows.find_by(content_version: 3)
  end

  # 회귀 방지: content_version>=2 인 "오프라인" 행(예: 신고 후 재생성된 오프라인)을 AI 워밍됨으로
  # 오판하지 않는다 — 버전 크기가 아니라 source==ai 가 판정 기준이어야 한다.
  test "an offline-only v2 (not yet AI) does not falsely count as warmed — warming still proceeds" do
    offline_v2 = Quiz.new(title: "온디맨드 mcq v2", created_by: Games::ContentProvider.system_user, book: @book,
                          scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                          content_version: 2, generation_status: :ready)
    Games::ContentProvider.build_questions(offline_v2, valid_mcq_set, source: :offline)
    offline_v2.save!

    service = inject_service(valid_mcq_set)
    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")

    v3 = system_mcq_rows.find_by(content_version: 3)
    assert_not_nil v3, "content_version>=2 라는 이유만으로 AI 워밍됨으로 오판하면 안 된다"
    assert_equal [ "ai" ], v3.quiz_questions.pluck(:source).uniq
    assert_equal 1, service.calls
  end

  # ── §2b 검증 후속 [LOW] 스테일 warming 리핑 ──────────────────────────────
  test "a stale warming row (past STALE_WARMING_AFTER) is reaped, allowing a fresh warm to proceed" do
    stale = Quiz.create!(title: "온디맨드 mcq v2 stale", created_by: Games::ContentProvider.system_user, book: @book,
                         scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                         content_version: 2, generation_status: :warming)
    stale.update_column(:updated_at, GenerateGameContentJob::STALE_WARMING_AFTER.ago - 1.minute)

    service = inject_service(valid_mcq_set)
    GenerateGameContentJob.new.perform(@book.id, "g56", "mcq")

    assert_not Quiz.exists?(stale.id), "스테일 warming 행은 리핑(폐기)된다"
    v2_after = system_mcq_rows.find_by(content_version: 2)
    assert_not_nil v2_after, "리핑 후 재선점으로 새 버전이 게시된다(하드크래시로 영구 고착되지 않는다)"
    assert_equal "ready", v2_after.generation_status
    assert_equal [ "ai" ], v2_after.quiz_questions.pluck(:source).uniq
    assert_equal 1, service.calls
  end

  # ── §2b 검증 후속 [LOW] 방송 실패가 커밋된 ready 게시를 되돌리지 않는다 ──
  test "a broadcast failure does not roll back an already-committed ready publish" do
    inject_service(valid_mcq_set)
    job = GenerateGameContentJob.new
    job.define_singleton_method(:broadcast_ready) { |_quiz| raise "boom broadcast" }

    assert_nothing_raised { job.perform(@book.id, "g56", "mcq") }

    v2 = system_mcq_rows.find_by(content_version: 2)
    assert_not_nil v2, "방송 실패에도 커밋된 ready 게시는 유지돼야 한다"
    assert_equal "ready", v2.generation_status
    assert_equal [ "ai" ], v2.quiz_questions.pluck(:source).uniq
  end
end
