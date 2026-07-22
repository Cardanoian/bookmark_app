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

  # 기본 sampler 는 결정적(최신=content_version desc 첫 행)으로 주입해 기존 회귀 단정(HIT·재생성·
  # ai-backed)이 세트 단위 랜덤(Phase 3 §3.5) 도입 후에도 안정적으로 성립하게 한다. 랜덤 선택 자체는
  # 별도 테스트에서 sampler seam 으로 검증한다.
  def provider(client: ConfiguredClient.new, rate_limiter: RateLimiter.new(store: ActiveSupport::Cache::MemoryStore.new),
               sampler: ->(candidates) { candidates.first })
    Games::ContentProvider.new(client: client, rate_limiter: rate_limiter, sampler: sampler)
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

  # 학급/학년 미상 학생: 게임 밴드는 최저(g12)로 결정된다(5~6학년 기본 매칭 금지, TODO 후속 정밀화).
  # 리졸버(생성 밴드)와 QuizPolicy(인가 밴드)가 game_band_for 를 공유하므로 g12 로 일치해 플레이 가능.
  test "a student without a classroom resolves to the lowest band (g12), not g56" do
    orphan = User.create!(school: @school, name: "무학급학생", role: :student, password: "password")
    quiz = provider.resolve(book: @book, surface: "quiz", user: orphan)
    assert_equal "g12", quiz.band, "학급/학년 미상 학생은 최저 밴드(g12)로 결정"
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
      second = provider.resolve(book: @book, surface: "quiz", user: @student) # 같은 mcq 축 히트
      assert_equal first.id, second.id, "같은 콘텐츠축은 캐시 히트로 같은 행 반환"
    end
  end

  # ── N1: 같은 mcq 축 재resolve 는 콘텐츠 단 1생성(게임 재구성 Phase 1: classic 표면 제거 → quiz 만) ──
  test "N1 — repeated resolve on the mcq surface generates the mcq content only once" do
    counting = CountingGeminiClient.new
    GenerateGameContentJob.draft_service_factory = -> { Ai::QuizDraftService.new(client: counting) }

    assert_enqueued_jobs 1, only: GenerateGameContentJob do
      2.times { provider.resolve(book: @book, surface: "quiz", user: @student) }
    end
    perform_enqueued_jobs

    assert_equal 1, counting.calls, "같은 mcq 축을 여러 번 resolve 해도 콘텐츠는 1회만 생성"
    assert_equal 1, Quiz.where(origin: :system, book_id: @book.id, content_axis: :mcq).where("content_version >= 2").count,
                 "워밍은 콘텐츠축당 1개의 새 버전만 만든다"
  end

  # 다른 표면(whoami→hint_reveal)은 별도 콘텐츠축이라 별도 생성.
  test "a different surface family maps to a different content_axis and warms separately" do
    provider.resolve(book: @book, surface: "quiz", user: @student)    # mcq
    provider.resolve(book: @book, surface: "whoami", user: @student)  # hint_reveal

    axes = Quiz.where(origin: :system, book_id: @book.id).pluck(:content_axis).uniq.sort
    assert_equal %w[hint_reveal mcq], axes.sort
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

  # ── 무게이트 롤아웃: 신고 임계(서로 다른 REPORT_HIDE_THRESHOLD 명) → 자동 숨김+재생성 ──
  test "record_report! hides+regenerates only when distinct reporters reach the threshold" do
    quiz = provider.resolve(book: @book, surface: "quiz", user: @student)
    reporter2 = User.create!(school: @school, classroom: @room_a, name: "신고자2", password: "password")

    assert_no_enqueued_jobs only: GenerateGameContentJob do
      first = provider.record_report!(quiz, @student) # 1명 신고 → 임계 미달
      assert first[:created]
      assert_not first[:hidden]
    end
    assert_not quiz.reload.reported?
    assert_equal 1, quiz.reports_count

    assert_enqueued_jobs 1, only: GenerateGameContentJob do
      second = provider.record_report!(quiz, reporter2) # 서로 다른 2번째 → 임계 도달
      assert second[:hidden]
    end
    assert quiz.reload.reported?, "서로 다른 #{Games::ContentProvider::REPORT_HIDE_THRESHOLD}명 신고 시 자동 숨김"
    assert_equal 2, quiz.reports_count
  end

  test "record_report! counts one report per user — a repeat report does not advance the threshold" do
    quiz = provider.resolve(book: @book, surface: "quiz", user: @student)

    assert provider.record_report!(quiz, @student)[:created]
    repeat = provider.record_report!(quiz, @student) # 같은 사용자 재신고
    assert_not repeat[:created], "같은 사용자의 재신고는 카운트되지 않는다(1인 1신고)"
    assert_not repeat[:hidden]
    assert_equal 1, quiz.reload.reports_count
    assert_not quiz.reported?
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

  # ── Phase 3 §3.5 문제은행식 세트 단위 랜덤 출제 ────────────────────────────
  # 세트가 여러 개면 resolve 는 준비된 후보들 중 하나를 sampler 로 고른다(기본 균등 랜덤).
  test "resolve passes the whole ready pool to the sampler when multiple sets exist" do
    provider.resolve(book: @book, surface: "quiz", user: @student)     # offline v1
    provider.regenerate(book: @book, surface: "quiz", user: @student)  # offline v2 → 풀 2세트

    seen = nil
    capturing = ->(candidates) { seen = candidates; candidates.first }
    prov = Games::ContentProvider.new(client: ConfiguredClient.new, sampler: capturing)
    prov.resolve(book: @book, surface: "quiz", user: @student)

    assert_equal 2, seen.size, "준비된 세트 전부(풀)를 sampler 에 넘긴다 — 세트 단위 랜덤 출제"
    assert_equal [ "system" ], seen.map(&:origin).uniq
  end

  # sampler seam 이 실제로 풀에서 서로 다른 세트를 고를 수 있다(랜덤 출제의 결정적 검증).
  test "the sampler seam can select different sets from the pool" do
    provider.resolve(book: @book, surface: "quiz", user: @student)     # v1
    provider.regenerate(book: @book, surface: "quiz", user: @student)  # v2

    latest = Games::ContentProvider.new(client: ConfiguredClient.new, sampler: ->(c) { c.first }).resolve(book: @book, surface: "quiz", user: @student)
    oldest = Games::ContentProvider.new(client: ConfiguredClient.new, sampler: ->(c) { c.last }).resolve(book: @book, surface: "quiz", user: @student)

    assert_not_equal latest.id, oldest.id, "sampler 에 따라 풀의 다른 세트가 출제된다"
    assert_operator latest.content_version, :>, oldest.content_version
  end

  # 세트가 하나뿐이면 그 세트를, 없으면 MISS→오프라인(오프라인 플로어 불변식).
  test "resolve serves the only set when one exists, and falls back to offline on MISS" do
    only = provider.resolve(book: @book, surface: "quiz", user: @student) # MISS → offline v1
    assert_equal only.id, provider.resolve(book: @book, surface: "quiz", user: @student).id, "세트 1개면 그 세트"
    assert_equal [ "offline" ], only.quiz_questions.pluck(:source).uniq, "MISS 는 오프라인 플로어(비활성 게이트는 Phase 4 유예)"
  end

  # 학생 승인 기여 세트도 같은 전국 풀의 후보가 된다(물질화 → resolve 풀 등장).
  test "an approved contribution set joins the same ready pool and can be served" do
    provider.resolve(book: @book, surface: "quiz", user: @student) # offline v1
    contribution = QuizContribution.create!(user: @student, book: @book, classroom: @room_a,
      content_axis: :mcq, band: :g56,
      payload: { "prompt" => "기여 질문?", "choices" => %w[가 나 다 라], "answer_index" => 2, "explanation" => "해설" })
    contributed_quiz = Games::ContributionPublisher.publish!(contribution)

    seen = nil
    prov = Games::ContentProvider.new(client: ConfiguredClient.new, sampler: ->(c) { seen = c; c.detect { |q| q.id == contributed_quiz.id } })
    served = prov.resolve(book: @book, surface: "quiz", user: @student)

    assert_includes seen.map(&:id), contributed_quiz.id, "기여 세트가 풀 후보에 포함된다"
    assert_equal [ "contributed" ], served.quiz_questions.pluck(:source).uniq
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

  # ── Phase 4 §2a 가용성 판정 ─────────────────────────────────────────────
  test "game_content_available? is false for AI-eligible books without reviewed content" do
    classic = Book.create!(title: "고전책", author: "저자", category: :classic)
    assert_not Games::ContentProvider.game_content_available?(book: classic, content_axis: :mcq, user: @student),
               "검수·승인 기여가 없는 고전은 샘플 문제를 만들지 않는다"
    assert_not Games::ContentProvider.game_content_available?(book: @book, content_axis: :mcq, user: @student),
               "summary 만 있는 책은 샘플 문제를 만들지 않는다"
  end

  test "game_content_available? is false for a bare book with no summary and no substantive content" do
    bare = Book.create!(title: "무명책", author: "무명", category: :recommended)
    assert_not Games::ContentProvider.game_content_available?(book: bare, content_axis: :mcq, user: @student),
               "AI-적격도 아니고 콘텐츠도 없는 책은 비활성"
  end

  test "game_content_available? ignores automatic content but honors contributed content" do
    bare = Book.create!(title: "무명책2", author: "무명", category: :recommended)
    # 오프라인만 있는 책은 여전히 비활성(일반 문제로 때우지 않는다).
    provider.resolve(book: bare, surface: "quiz", user: @student) # offline v1 생성
    assert_not Games::ContentProvider.game_content_available?(book: bare, content_axis: :mcq, user: @student),
               "offline 세트만 있는 책은 비활성"

    QuizQuestion.where(quiz: Quiz.where(book: bare, origin: :system, content_axis: :mcq)).update_all(source: QuizQuestion.sources.fetch("ai"))
    assert_not Games::ContentProvider.game_content_available?(book: bare, content_axis: :mcq, user: @student),
               "자동 AI 세트도 검수 전에는 비활성"

    # 학생 승인 기여(contributed)가 물질화되면 가용.
    contribution = QuizContribution.create!(user: @student, book: bare, classroom: @room_a,
      content_axis: :mcq, band: :g56,
      payload: { "prompt" => "기여?", "choices" => %w[가 나 다 라], "answer_index" => 1, "explanation" => "해설" })
    Games::ContributionPublisher.publish!(contribution)
    assert Games::ContentProvider.game_content_available?(book: bare, content_axis: :mcq, user: @student),
           "contributed 콘텐츠가 있으면 가용"
  end

  # ── Phase 4 §1d 트리거: 줄거리 미확인 책 워밍 시 BookSummaryJob 도 함께 큐잉 ──
  # classic 책(AI-적격, 가용성 게이트 통과)으로 검증한다 — bare recommended 책은 게이트가 resolve
  # 전에 리다이렉트시켜 실제로는 이 트리거에 도달하지 못하는 경로다(code-review 후속, §2c 상호작용).
  test "resolve enqueues a BookSummaryJob for a summary-blank, unchecked classic book (the actual reachable path)" do
    classic = Book.create!(title: "고전줄거리없는책", author: "저자", category: :classic)
    assert_enqueued_jobs 1, only: BookSummaryJob do
      provider.resolve(book: classic, surface: "quiz", user: @student)
    end
  end

  test "resolve does not enqueue a BookSummaryJob when the book already has a summary" do
    assert_no_enqueued_jobs only: BookSummaryJob do
      provider.resolve(book: @book, surface: "quiz", user: @student) # @book 은 summary 보유
    end
  end

  test "resolve does not enqueue a BookSummaryJob when already checked (idempotent trigger)" do
    bare = Book.create!(title: "확인된책", author: "저자", category: :recommended, summary_checked_at: Time.current)
    assert_no_enqueued_jobs only: BookSummaryJob do
      provider.resolve(book: bare, surface: "quiz", user: @student)
    end
  end

  test "resolve enqueues no BookSummaryJob without an API key (offline only)" do
    bare = Book.create!(title: "무키책", author: "저자", category: :recommended)
    unconfigured = Games::ContentProvider.new(client: Ai::GeminiClient.new) # test 환경 = 무키
    assert_no_enqueued_jobs only: BookSummaryJob do
      unconfigured.resolve(book: bare, surface: "quiz", user: @student)
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
