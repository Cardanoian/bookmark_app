require "test_helper"

# Phase 2b §2b.1 — 콘텐츠축 캐시-우선 리졸버. 미스=오프라인 즉시(아동 무대기) + 워밍 1적재,
# 히트=Gemini 0, N1=5표면이 mcq 를 공유해 콘텐츠 1생성, 스코프 플래그·rate limit·신고 경로.
class Games::ContentProviderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # ContentProvider @client 은 configured? 만 본다(생성 결정용). generate 는 워밍 잡이 담당.
  class ConfiguredClient
    def configured? = true
    def generate(**) = nil
  end

  # 워밍 잡에 주입해 generate 호출 횟수를 세는 클라이언트(유효 mcq 응답 반환 → moderator 통과).
  class CountingGeminiClient
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def configured? = true

    def generate(**)
      @calls += 1
      { "questions" => (1..5).map { |i| { "prompt" => "질문#{i}", "choices" => [ "가#{i}", "나#{i}", "다#{i}", "라#{i}" ], "answer_index" => i % 4, "explanation" => "해설#{i}", "difficulty" => 2 } } }
    end
  end

  setup do
    @school = School.create!(name: "리졸버초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1) # grade5 → g56
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @student = User.create!(school: @school, classroom: @room_a, name: "리졸버학생", password: "password")
    @book = Book.create!(title: "리졸버책", author: "김작가", summary: "잎싹의 자유를 향한 모험 이야기.", category: :recommended)
    enable_flag(true)
  end

  teardown { GenerateGameContentJob.reset_factories! }

  def enable_flag(global, overrides = {})
    AppSetting.set("feature_flags", { "on_demand_games" => global }.merge(overrides))
  end

  def provider(client: ConfiguredClient.new, rate_limiter: RateLimiter.new(store: ActiveSupport::Cache::MemoryStore.new))
    Games::ContentProvider.new(client: client, rate_limiter: rate_limiter)
  end

  # ── 미스: 오프라인 즉시 + 워밍 1적재 ─────────────────────────────────────
  test "MISS returns a ready offline system quiz immediately and enqueues exactly one warming job" do
    quiz = nil
    assert_enqueued_jobs 1, only: GenerateGameContentJob do
      quiz = provider.resolve(book: @book, surface: "quiz", user: @student)
    end

    assert_equal "system", quiz.origin
    assert_equal "ready", quiz.generation_status, "generation_status 는 내부 캐시 상태 — 플레이어 게이트가 아니다"
    assert_equal "g56", quiz.band, "band 는 서버가 학급 학년으로 결정(사용자 입력 아님)"
    assert_equal ReadingDomain::CONTENT_COUNTS[:mcq], quiz.quiz_questions.count
    assert_equal [ "offline" ], quiz.quiz_questions.pluck(:source).uniq, "미스 즉시 세트는 결정적 오프라인"
  end

  # 아동 무대기: resolve 반환 시점엔 아직 어떤 generate 도 일어나지 않는다.
  test "the child never waits — resolve returns before any Gemini generation happens" do
    counting = CountingGeminiClient.new
    GenerateGameContentJob.draft_service_factory = -> { Ai::QuizDraftService.new(client: counting) }

    quiz = provider.resolve(book: @book, surface: "quiz", user: @student)

    assert_equal 0, counting.calls, "resolve 는 워밍(Gemini)을 기다리지 않는다"
    assert quiz.quiz_questions.any?, "이미 플레이 가능한 오프라인 문항이 채워져 있다"
  end

  # ── 히트: Gemini 0, 워밍 잡 없음 ────────────────────────────────────────
  test "HIT returns the cached row with zero Gemini work and no warming job" do
    first = provider.resolve(book: @book, surface: "quiz", user: @student) # 미스로 오프라인 생성

    assert_no_enqueued_jobs do
      second = provider.resolve(book: @book, surface: "classic", user: @student) # 같은 mcq 축 히트
      assert_equal first.id, second.id, "같은 콘텐츠축은 캐시 히트로 같은 행 반환"
    end
  end

  # ── N1: quiz·classic 이 mcq 를 공유 → 콘텐츠 단 1생성 ────────────────────────────
  test "N1 — sequential resolve across mcq surfaces generates the mcq content only once" do
    counting = CountingGeminiClient.new
    GenerateGameContentJob.draft_service_factory = -> { Ai::QuizDraftService.new(client: counting) }

    assert_enqueued_jobs 1, only: GenerateGameContentJob do
      %w[quiz classic].each do |surface|
        provider.resolve(book: @book, surface: surface, user: @student)
      end
    end
    perform_enqueued_jobs

    assert_equal 1, counting.calls, "quiz/classic 2표면에 걸쳐 mcq 콘텐츠는 1회만 생성"
    assert_equal 1, Quiz.where(origin: :system, book_id: @book.id, content_axis: :mcq).where("content_version >= 2").count,
                 "워밍은 콘텐츠축당 1개의 새 버전만 만든다"
  end

  # 다른 콘텐츠축(vocab→matching)은 별도 생성.
  test "a different surface family maps to a different content_axis and warms separately" do
    provider.resolve(book: @book, surface: "quiz", user: @student)   # mcq
    provider.resolve(book: @book, surface: "vocab", user: @student)  # matching

    axes = Quiz.where(origin: :system, book_id: @book.id).pluck(:content_axis).uniq.sort
    assert_equal %w[matching mcq], axes.sort
  end

  # ── 스코프 플래그(C3) ───────────────────────────────────────────────────
  test "classroom scope isolation — room A warms, room B degrades to offline only" do
    enable_flag(true, { "on_demand_games:classroom:#{@room_b.id}" => false })
    student_b = User.create!(school: @school, classroom: @room_b, name: "B반학생", password: "password")

    assert_enqueued_jobs 1, only: GenerateGameContentJob do
      provider.resolve(book: @book, surface: "quiz", user: @student) # A반 → 워밍
    end
    assert_no_enqueued_jobs do
      quiz_b = provider.resolve(book: @book, surface: "whoami", user: student_b) # B반 → 오프라인만
      assert_equal "offline", quiz_b.quiz_questions.first.source
    end
  end

  test "global kill switch (flag=false) degrades everyone to offline only" do
    enable_flag(false)

    assert_no_enqueued_jobs do
      quiz = provider.resolve(book: @book, surface: "quiz", user: @student)
      assert_equal "offline", quiz.quiz_questions.first.source, "하드 kill → 오프라인만"
    end
  end

  # ── rate limit / 예산 초과 → 오프라인 강등 ──────────────────────────────
  test "over the per-user warming limit, resolve degrades to offline (no warming job)" do
    store = ActiveSupport::Cache::MemoryStore.new
    limiter = RateLimiter.new(store: store)
    RateLimiter::WARMING_PER_USER[:limit].times { limiter.warming_allowed?(@student.id) } # 한도 소진

    assert_no_enqueued_jobs do
      quiz = provider(rate_limiter: limiter).resolve(book: @book, surface: "quiz", user: @student)
      assert_equal "offline", quiz.quiz_questions.first.source
    end
  end

  # ── 신고 경로: 숨김 + 재생성 트리거, 이후 resolve 는 숨긴 행을 주지 않는다 ──
  test "report! hides the row, enqueues regeneration, and later resolve does not serve the reported row" do
    quiz = provider.resolve(book: @book, surface: "quiz", user: @student)

    assert_enqueued_jobs 1, only: GenerateGameContentJob do
      Games::ContentProvider.new(client: ConfiguredClient.new).report!(quiz)
    end
    assert quiz.reload.reported?, "신고 행은 숨김 처리(reported)"

    replacement = provider.resolve(book: @book, surface: "quiz", user: @student)
    assert_not_equal quiz.id, replacement.id, "신고된 행은 다시 서빙되지 않는다"
    assert_not replacement.reported?
  end

  # ── §2b 검증 후속 [LOW] 오프라인 전용 축의 영구 고착 방지(재시도, 백오프) ──
  test "a freshly created offline-only HIT does not retry warming (within RETRY_GRACE)" do
    provider.resolve(book: @book, surface: "quiz", user: @student) # MISS → offline v1 + 1 job enqueued
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      provider.resolve(book: @book, surface: "quiz", user: @student) # HIT, 방금 생성돼 아직 grace 이내
    end
  end

  test "an aged offline-only HIT retries warming once, then backs off under the axis cooldown" do
    # 쿨다운은 rate_limiter(=축 단위 카운터 저장소) 상태에 의존하므로, `provider` 헬퍼를 매번 새로
    # 호출하면(기본 인자가 호출마다 새 MemoryStore 를 만든다) 카운터가 이어지지 않는다 — 같은
    # provider 인스턴스를 재사용해야 쿨다운이 실제로 작동하는지 검증할 수 있다.
    my_provider = provider
    quiz = my_provider.resolve(book: @book, surface: "quiz", user: @student) # MISS → offline v1
    clear_enqueued_jobs
    quiz.update_column(:created_at, (Games::ContentProvider::RETRY_GRACE + 1.minute).ago)

    assert_enqueued_jobs 1, only: GenerateGameContentJob do
      my_provider.resolve(book: @book, surface: "quiz", user: @student) # HIT, 오래된 오프라인 → 재시도
    end

    assert_no_enqueued_jobs do
      my_provider.resolve(book: @book, surface: "quiz", user: @student) # 축 쿨다운에 걸려 즉시 재시도 안 함
    end
  end

  test "an ai-backed cached row never triggers a retry-warming attempt even if aged" do
    provider.resolve(book: @book, surface: "quiz", user: @student) # offline v1

    v2 = Quiz.new(title: "온디맨드 mcq v2", created_by: Games::ContentProvider.system_user, book: @book,
                  scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                  content_version: 2, generation_status: :ready)
    Games::ContentProvider.build_questions(v2, Ai::QuizDraftService.new.offline_set(@book, :g56, :mcq), source: :ai)
    v2.save!
    v2.update_column(:created_at, (Games::ContentProvider::RETRY_GRACE + 1.minute).ago)
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      cached = provider.resolve(book: @book, surface: "quiz", user: @student) # HIT → v2(ai-backed)
      assert_equal v2.id, cached.id
    end
  end

  # ── Phase 3 §3.4 재생성(다시 뽑기): 새 content_version, 다음 resolve 가 최신 서빙 ──
  test "regenerate creates a fresh higher content_version served by the next resolve" do
    original = provider.resolve(book: @book, surface: "quiz", user: @student)
    regenerateed = provider.regenerate(book: @book, surface: "quiz", user: @student)

    assert_operator regenerateed.content_version, :>, original.content_version, "재생성은 새 버전을 만든다"
    assert_not_equal original.id, regenerateed.id

    served = provider.resolve(book: @book, surface: "quiz", user: @student)
    assert_equal regenerateed.id, served.id, "다음 resolve 는 재생성한 최신 버전을 서빙(content_version desc)"
  end

  # M1: 다시 뽑기(오프라인 재생성)는 rate limit 밖이라 무제한 DB 증식이 가능했다 → per-user 시간당 한도.
  test "regenerate_allowed? throttles per user after the hourly limit" do
    limiter = RateLimiter.new(store: ActiveSupport::Cache::MemoryStore.new)
    prov = provider(rate_limiter: limiter) # 동일 인스턴스·저장소 재사용(카운터 연속)

    Games::ContentProvider::REGENERATE_PER_USER[:limit].times do
      assert prov.regenerate_allowed?(@student), "시간당 한도 이내 다시 뽑기는 허용"
    end
    refute prov.regenerate_allowed?(@student), "한도 초과 다시 뽑기는 차단(오프라인 무제한 증식 방지)"
  end

  # ── Phase 3 §3.5 warm 사전생성(A5): band×axis 워밍 큐잉·예산·kill switch·무키 강등 ──
  test "warm! pre-enqueues one warming job per band and content_axis" do
    assert_enqueued_jobs 1, only: GenerateGameContentJob do
      assert_equal 1, provider.warm!(@book, bands: [ :g56 ], axes: [ :mcq ])
    end
  end

  test "warm! degrades to nothing without an API key (offline only)" do
    unconfigured = Games::ContentProvider.new(client: Ai::GeminiClient.new) # test 환경 = 무키
    assert_no_enqueued_jobs do
      assert_equal 0, unconfigured.warm!(@book, bands: [ :g56 ], axes: [ :mcq ])
    end
  end

  test "warm! respects the global kill switch" do
    enable_flag(false)
    assert_no_enqueued_jobs do
      assert_equal 0, provider.warm!(@book, bands: [ :g56 ], axes: [ :mcq ])
    end
  end

  test "an assigned book is warmed to AI-backed content before the first play (no cold-first-offline)" do
    counting = CountingGeminiClient.new
    GenerateGameContentJob.draft_service_factory = -> { Ai::QuizDraftService.new(client: counting) }

    perform_enqueued_jobs do
      provider.warm!(@book, bands: [ :g56 ], axes: [ :mcq ])
    end
    assert_equal 1, counting.calls, "첫 플레이 전에 AI 생성이 수행된다"

    assert_no_enqueued_jobs do
      quiz = provider.resolve(book: @book, surface: "quiz", user: @student) # 첫 플레이 = HIT
      assert_includes quiz.quiz_questions.pluck(:source), "ai", "첫 플레이가 AI 워밍 콘텐츠를 만난다"
    end
  end

  # ── §2b 검증 후속 [LOW] find_or_create_offline 재경쟁 유한 재시도 ────────
  class FlakyContentProvider < Games::ContentProvider
    attr_accessor :fail_times

    def persist_offline(*args)
      if @fail_times.to_i.positive?
        @fail_times -= 1
        raise ActiveRecord::RecordNotUnique, "simulated race"
      end
      super
    end
  end

  test "find_or_create_offline bounded-retries repeated RecordNotUnique races within the limit" do
    flaky = FlakyContentProvider.new(client: ConfiguredClient.new)
    flaky.fail_times = Games::ContentProvider::OFFLINE_RACE_RETRY_LIMIT - 1 # 마지막 허용 시도에서 성공

    quiz = flaky.resolve(book: @book, surface: "quiz", user: @student)
    assert_equal "offline", quiz.quiz_questions.first.source
  end

  test "find_or_create_offline gives up (re-raises) after exceeding the retry bound" do
    flaky = FlakyContentProvider.new(client: ConfiguredClient.new)
    flaky.fail_times = 999 # 항상 실패(무한 경쟁 시뮬레이션) — 무한 루프 없이 유한하게 포기해야 한다

    assert_raises(ActiveRecord::RecordNotUnique) do
      flaky.resolve(book: @book, surface: "quiz", user: @student)
    end
  end
end
