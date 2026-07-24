require "test_helper"

# Stage 2 — 큐레이션 문항 서빙 통합. 큐레이션 있는 책은 resolve 가 source: curated 문항의 Quiz 를
# 물질화(MISS)하고 여러 밴드에서 각각 curated 로 서빙하며, fetch_ready 는 curated·offline 공존 시
# curated 를 우선하고, 워밍(GenerateGameContentJob)은 억제된다.
class Games::ContentProviderCuratedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class ConfiguredClient
    def configured? = true
    def generate(**) = nil
  end

  setup do
    @school = School.create!(name: "큐레이션초")
    @room = Classroom.create!(school: @school, grade: 5, class_no: 1) # grade5 → g56
    @student = User.create!(school: @school, classroom: @room, name: "큐레이션학생", password: "password")
    @book = Book.create!(title: "큐레이션책", author: "김작가", summary: "잎싹의 자유를 향한 모험 이야기.", category: :recommended)
    CuratedQuiz.create!(book: @book, content_axis: :mcq, payload: [
      { "prompt" => "주인공은?", "choices" => %w[잎싹 나그네 청둥오리 족제비], "answer_index" => 0, "explanation" => "잎싹.", "difficulty" => 1 }
    ])
    enable_flag(true)
  end

  teardown { GenerateGameContentJob.reset_factories! }

  def enable_flag(global, overrides = {})
    AppSetting.set("feature_flags", { "on_demand_games" => global }.merge(overrides))
  end

  def provider(client: ConfiguredClient.new, rate_limiter: RateLimiter.new(store: ActiveSupport::Cache::MemoryStore.new),
               sampler: ->(candidates) { candidates.first })
    Games::ContentProvider.new(client: client, rate_limiter: rate_limiter, sampler: sampler)
  end

  # ── MISS 물질화: curated 문항 Quiz, 워밍 억제 ────────────────────────────
  test "a curated book resolves to a curated-source quiz on MISS and enqueues no warming job" do
    quiz = nil
    assert_no_enqueued_jobs only: GenerateGameContentJob do
      quiz = provider.resolve(book: @book, surface: "quiz", user: @student)
    end

    assert_equal "system", quiz.origin
    assert_equal "g56", quiz.band
    assert_equal [ "curated" ], quiz.quiz_questions.pluck(:source).uniq, "큐레이션 검수 문항이 물질화된다"
    assert_equal "주인공은?", quiz.quiz_questions.first.prompt
  end

  # 여러 밴드(학년)에서 각각 curated 로 서빙된다(밴드 팬아웃 자동 처리).
  test "different bands each materialize the curated set" do
    g56 = provider.resolve(book: @book, surface: "quiz", user: @student) # g56

    room_low = Classroom.create!(school: @school, grade: 1, class_no: 9) # grade1 → g12
    junior = User.create!(school: @school, classroom: room_low, name: "저학년학생", password: "password")
    g12 = provider.resolve(book: @book, surface: "quiz", user: junior)

    assert_equal "g56", g56.band
    assert_equal "g12", g12.band
    assert_not_equal g56.id, g12.id, "밴드별로 별도 Quiz 로 물질화"
    assert_equal [ "curated" ], g12.quiz_questions.pluck(:source).uniq
  end

  # ── fetch_ready: curated·offline 공존 시 curated 우선(결정적 sampler) ─────
  test "fetch_ready prefers curated sets over coexisting offline sets" do
    # 큐레이션 이전에 만들어진 제네릭 offline 세트(레거시 캐시)를 손수 심는다.
    offline = Quiz.new(title: "온디맨드 mcq", created_by: Games::ContentProvider.system_user, book: @book,
                       scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                       content_version: 1, generation_status: :ready)
    Games::ContentProvider.build_questions(offline, Ai::QuizDraftService.new.offline_set(@book, :g56, :mcq), source: :offline)
    offline.save!

    # 큐레이션 세트(더 낮은 버전이어도 우선). 결정적 sampler(candidates.first)로 검증.
    curated = Quiz.new(title: "온디맨드 mcq c", created_by: Games::ContentProvider.system_user, book: @book,
                       scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                       content_version: 2, generation_status: :ready)
    Games::ContentProvider.build_questions(curated, Games::CuratedContent.set_for(@book, :mcq), source: :curated)
    curated.save!

    seen = nil
    prov = Games::ContentProvider.new(client: ConfiguredClient.new, sampler: ->(c) { seen = c; c.first })
    served = prov.resolve(book: @book, surface: "quiz", user: @student)

    assert_equal [ curated.id ], seen.map(&:id), "sampler 에는 curated 세트만 넘어간다(offline 배제)"
    assert_equal curated.id, served.id
    assert_equal [ "curated" ], served.quiz_questions.pluck(:source).uniq
  end

  # ── 가용성 게이트 ───────────────────────────────────────────────────────
  test "game_content_available? is true for a curated book even without summary/classic" do
    bare = Book.create!(title: "무명큐레이션책", author: "무명", category: :recommended) # summary·classic 아님
    CuratedQuiz.create!(book: bare, content_axis: :hint_reveal, payload: [
      { "answer" => "잎싹", "hints" => [ "암탉", "두 글자" ], "explanation" => "", "difficulty" => 1 }
    ])
    assert Games::ContentProvider.game_content_available?(book: bare, content_axis: :hint_reveal, user: @student),
           "큐레이션 검수 문항이 있으면 가용"
    assert_not Games::ContentProvider.game_content_available?(book: bare, content_axis: :mcq, user: @student),
               "큐레이션 없는 축은 여전히 비활성(AI-부적격·콘텐츠 없음)"
  end

  # ── 워밍 억제: HIT·재시도·warm! 모두 잡을 넣지 않는다 ────────────────────
  test "a curated book never enqueues warming on repeated resolve (HIT path)" do
    provider.resolve(book: @book, surface: "quiz", user: @student) # MISS → curated 물질화
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      provider.resolve(book: @book, surface: "quiz", user: @student) # HIT
    end
  end

  test "an aged curated HIT does not retry warming (warming suppressed for curated books)" do
    quiz = provider.resolve(book: @book, surface: "quiz", user: @student)
    clear_enqueued_jobs
    quiz.update_column(:created_at, (Games::ContentProvider::RETRY_GRACE + 1.minute).ago)

    assert_no_enqueued_jobs do
      provider.resolve(book: @book, surface: "quiz", user: @student) # 오래된 세트여도 재워밍 억제
    end
  end

  # warm!(사전 큐잉)은 큐레이션 축에도 잡을 적재할 수 있으나, 잡 자체가 조기 반환해 검수 문항을
  # ai 로 덮지 않는다(무해). 워밍 억제의 최종 방어선은 GenerateGameContentJob 의 큐레이션 가드다.
  test "warm! may enqueue a job for a curated axis but the job no-ops (no ai overwrite)" do
    perform_enqueued_jobs do
      provider.warm!(@book, bands: [ :g56 ], axes: [ :mcq ])
    end
    assert_equal 0, Quiz.where(origin: :system, book_id: @book.id).joins(:quiz_questions)
                        .where(quiz_questions: { source: :ai }).count, "큐레이션 책에는 ai 문항이 생기지 않는다"
  end

  # 스테일 워밍 잡이 실행돼도 큐레이션 책은 조기 반환해 검수 문항을 ai 로 덮지 않는다.
  test "GenerateGameContentJob returns early for a curated book (no ai overwrite)" do
    assert_no_difference -> { Quiz.where(origin: :system, book_id: @book.id).count } do
      GenerateGameContentJob.perform_now(@book.id, "g56", "mcq")
    end
    assert_equal 0, Quiz.where(origin: :system, book_id: @book.id).joins(:quiz_questions)
                        .where(quiz_questions: { source: :ai }).count, "ai 문항이 생기지 않는다"
  end
end
