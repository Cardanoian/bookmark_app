require "test_helper"

# 게임 재구성 Phase 4 §2 — 가용성 게이트. 콘텐츠를 만들 수 없는 책(AI-적격 아님·기여/AI 콘텐츠 없음)은
# 퀴즈·나는 누구게?를 **일반 문제로 때우지 않고 비활성**한다: 독서활동에서 칩을 숨기고(§2b),
# 직접 URL 진입은 오프라인 세트를 만들지 않고 리다이렉트(§2c). 창작 소셜(책 소개·뒷이야기)은 항상 가능.
class GamesContentGateTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "게이트초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1) # g56
    @student = User.create!(school: @school, classroom: @classroom, name: "게이트학생", password: "password")
    @bare = Book.create!(title: "무명게이트책", author: "무명", category: :recommended)          # AI-부적격
    @available = Book.create!(title: "가용게이트책", author: "저자", summary: "긴 줄거리.", category: :recommended)
    login_as @student
  end

  # ── §2b 표시 게이트: 비활성 책은 퀴즈·나는 누구게? 칩 없음, 책 소개·뒷이야기 칩 있음 ──
  test "reading activity hides quiz/whoami chips for an unavailable book but keeps the creative ones" do
    get reading_activity_path(book_id: @bare.id)
    assert_response :success

    assert_select "a[href=?]", games_quiz_play_path(book_id: @bare.id), count: 0    # 퀴즈 칩 숨김
    assert_select "a[href=?]", games_whoami_play_path(book_id: @bare.id), count: 0  # 나는 누구게? 칩 숨김
    assert_select "a[href=?]", games_book_play_path(book_id: @bare.id)              # 책 소개 대결은 항상 표시
    assert_select "a[href=?]", games_sequel_play_path(book_id: @bare.id)            # 뒷이야기는 항상 표시
  end

  test "reading activity shows quiz/whoami chips for an AI-eligible (summary) book" do
    get reading_activity_path(book_id: @available.id)
    assert_response :success

    assert_select "a[href=?]", games_quiz_play_path(book_id: @available.id)    # 퀴즈 칩 표시
    assert_select "a[href=?]", games_whoami_play_path(book_id: @available.id)  # 나는 누구게? 칩 표시
  end

  # ── §2c 플레이 게이트: 비활성 책 직접 진입 → 리다이렉트, 오프라인 세트 미생성 ──
  # 게이트 상호작용 고정(code-review 후속 LOW): resolve 를 아예 안 부르므로 content_provider 의
  # §1d 온디맨드 트리거(maybe_enqueue_book_summary)도 걸리지 않는다 — 비활성 책의 Gemini 확인은
  # 이 경로가 아니라 reading_activities 자가치유가 담당함을 명시적으로 고정한다(아래 섹션).
  test "quiz play on an unavailable book redirects without materializing an offline quiz" do
    assert_no_difference -> { Quiz.count } do
      assert_no_enqueued_jobs only: BookSummaryJob do
        get games_quiz_play_path(book_id: @bare.id)
      end
    end
    assert_redirected_to reading_activity_path(book_id: @bare.id)
    assert_match "다른 활동", flash[:notice]
  end

  test "whoami play on an unavailable book redirects without materializing an offline quiz or attempt" do
    assert_no_difference [ -> { Quiz.count }, -> { QuizAttempt.count } ] do
      assert_no_enqueued_jobs only: BookSummaryJob do
        get games_whoami_play_path(book_id: @bare.id)
      end
    end
    assert_redirected_to reading_activity_path(book_id: @bare.id)
  end

  # ── 회귀: AI-적격 책은 기존대로 오프라인 즉시 서빙(무대기·게이트 통과) ──
  test "quiz play on an available book still serves an offline system quiz immediately (no regression)" do
    get games_quiz_play_path(book_id: @available.id)
    assert_response :success

    quiz = Quiz.where(origin: :system, book_id: @available.id, content_axis: :mcq).last
    assert_equal "ready", quiz.generation_status
    assert_equal "offline", quiz.quiz_questions.first.source
  end

  # ── §2c 다시 뽑기(regenerate) 게이트(code-review 후속 LOW): 조작된 POST 로도 비활성 책에
  #    오프라인 Quiz 를 물질화할 수 없다 ──
  test "regenerate on an unavailable book redirects without materializing an offline quiz" do
    assert_no_difference -> { Quiz.count } do
      post games_regenerate_path, params: { book_id: @bare.id, surface: "quiz" }
    end
    assert_redirected_to reading_activity_path(book_id: @bare.id)
  end

  test "regenerate on an available book still creates a new content_version (no regression)" do
    get games_quiz_play_path(book_id: @available.id) # 최초 오프라인 v1
    original = Quiz.where(origin: :system, book_id: @available.id, content_axis: :mcq).last

    post games_regenerate_path, params: { book_id: @available.id, surface: "quiz" }

    rerolled = Quiz.where(origin: :system, book_id: @available.id, content_axis: :mcq).order(:content_version).last
    assert_operator rerolled.content_version, :>, original.content_version
    assert_redirected_to games_quiz_play_path(book_id: @available.id)
  end

  # ── Phase 4 자가치유(code-review 후속 [중요]): 게이트가 resolve 를 우회시켜 §1d 온디맨드
  #    트리거가 비활성 책에 절대 도달하지 못하므로, 독서활동 화면 자체가 미확인 책을 볼 때
  #    Gemini 확인을 직접 부트스트랩한다(무키면 큐잉 안 함, 잡은 멱등) ──
  test "reading activity bootstraps a BookSummaryJob for an unchecked book when a Gemini key is configured" do
    with_configured_gemini_client do
      assert_enqueued_jobs 1, only: BookSummaryJob do
        get reading_activity_path(book_id: @bare.id)
      end
    end
  end

  test "reading activity enqueues no BookSummaryJob without an API key (offline only, matches test env)" do
    assert_no_enqueued_jobs only: BookSummaryJob do
      get reading_activity_path(book_id: @bare.id)
    end
  end

  test "reading activity does not bootstrap a BookSummaryJob for a book that already has a summary" do
    with_configured_gemini_client do
      assert_no_enqueued_jobs only: BookSummaryJob do
        get reading_activity_path(book_id: @available.id) # summary 보유 → 이미 확인된 셈
      end
    end
  end

  test "reading activity does not re-bootstrap a BookSummaryJob for an already-checked unknown book" do
    checked = Book.create!(title: "이미확인된책", author: "무명", category: :recommended,
                           summary_checked_at: Time.current) # Gemini 가 모른다고 이미 확인함
    with_configured_gemini_client do
      assert_no_enqueued_jobs only: BookSummaryJob do
        get reading_activity_path(book_id: checked.id)
      end
    end
  end

  private

  # Ai::GeminiClient.new 을 configured?=true 로 임시 교체한다(Minitest 6 은 minitest/mock 미제공 —
  # book_summary_job_test.rb 의 run_with_key 선례와 동일 패턴).
  def with_configured_gemini_client
    configured = Object.new
    def configured.configured? = true
    Ai::GeminiClient.define_singleton_method(:new) { |*, **| configured }
    yield
  ensure
    Ai::GeminiClient.singleton_class.send(:remove_method, :new)
  end
end
