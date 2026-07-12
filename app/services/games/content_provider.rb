module Games
  # 콘텐츠축 캐시-우선 리졸버(Phase 2b §2b.1). 학생이 어떤 표면(surface)으로 게임에 진입하든
  # 표면을 **콘텐츠축(content_axis)** 으로 접어(N1) 캐시를 조회하고, 없으면 **책 파생 결정적
  # 오프라인 system Quiz 를 즉시 만들어 반환**한다. 아동은 **결코 대기하지 않는다** —
  # generation_status 는 플레이어에게 노출되지 않는 내부 캐시 상태일 뿐, 게이트가 아니다.
  #
  # 흐름(resolve):
  #   ① surface → content_axis (SURFACE_MAP; 5표면이 mcq 를 공유 → 콘텐츠축당 1생성).
  #   ② band = ReadingDomain.band_for(user.classroom&.grade) — **서버 결정**(사용자 입력 불신).
  #   ③ 캐시 HIT: origin=system·해당 축·최신 content_version·ready·미신고 → 즉시 반환(Gemini 0).
  #      단, 그 행이 AI 로 게시된 적 없이 **오프라인만으로 RETRY_GRACE 이상 지속**됐다면(첫 워밍이
  #      거부/실패했거나 무키였던 경우 영구 오프라인에 갇히지 않도록) 축 단위 쿨다운 하에 재워밍을
  #      시도한다(§2b 검증 후속 [LOW]). 방금 만든 오프라인(정상 워밍 진행 중일 수 있는 창)은
  #      RETRY_GRACE 미만이라 재시도하지 않아 N1 을 어기지 않는다.
  #   ④ 캐시 MISS: 오프라인 결정적 system Quiz(source=offline, content_version=1, ready) 를
  #      insert(rescue RecordNotUnique → 재조회, 유한 재시도)로 만들어 **즉시 반환**하고,
  #      (키 있음 · 스코프 플래그 on · rate limit/예산 OK) 이면 `GenerateGameContentJob` 을
  #      백그라운드 워밍으로 1건 적재한다. 키가 없으면 오프라인만(잡 없음).
  #
  # ⚠️ MISS 즉시 반환에는 content_set(AI 경로)이 아니라 offline_set(네트워크 0·결정적)을 쓴다 —
  #    content_set 은 키가 있으면 동기 Gemini 호출로 아동을 대기시키므로 "미스=오프라인 즉시"
  #    불변식(A.1 P1)에 위배된다. AI 는 오직 워밍 잡에서만 붙는다.
  class ContentProvider
    # 표면 → 콘텐츠축. mcq 를 5표면이 공유(N1 콘텐츠축 캐시 = 비용 봉인).
    SURFACE_MAP = {
      "quiz" => :mcq, "golden" => :mcq, "bingo" => :mcq, "battle" => :mcq, "classic" => :mcq,
      "vocab" => :matching,
      "whoami" => :hint_reveal,
      "balance" => :balance_vote
    }.freeze

    # 온디맨드 게임 전역 kill switch + 스코프 플래그 키(C3).
    FEATURE_FLAG = "on_demand_games"

    # 오프라인만 있는 캐시 행이 이 시간 이상 그대로면(정상 워밍 잡이라면 이미 끝났을 시간),
    # 첫 워밍이 거부/실패됐거나 아예 시도되지 않았다고 보고 재시도 대상으로 삼는다(§2b LOW).
    # 이 값보다 짧은 사이에는 재시도하지 않아 방금 MISS 로 만든 오프라인(정상 워밍 진행 중일 수
    # 있는 창)에 대해 중복 워밍을 걸지 않는다 — N1(콘텐츠축당 1생성) 을 지킨다.
    RETRY_GRACE = 15.minutes

    # 오프라인 전용 축 재시도의 빈도 제한(축 단위 쿨다운). 매 HIT 마다 재시도를 걸면 낭비이므로
    # 콘텐츠축당 이 주기에 최대 1회만 재워밍을 시도한다.
    RETRY_COOLDOWN = 1.hour

    # 오프라인(offline)→오프라인(재경쟁) 재시도 상한. SQLite 는 단일 writer 라 사실상 무해하나,
    # 다중 writer 배포(예: 향후 Postgres 전환)에서도 무한 루프 없이 방어적으로 동작하게 한다.
    OFFLINE_RACE_RETRY_LIMIT = 3

    # 다시 뽑기 per-user 스로틀(§2b 검증 후속 [MED] M1). regenerate 는 캐시 유무와 무관하게 항상
    # 새 content_version 오프라인 행 + 문항을 만들므로, 무제한 연타 시 AI 비용(워밍은 이미 rate limit)
    # 과 별개로 **DB/스토리지가 무한 증식**한다. 오프라인 재생성 빈도 자체를 시간당 한도로 캡한다.
    REGENERATE_PER_USER = { limit: 10, period: 1.hour }.freeze

    # origin=system Quiz 의 소유자(created_by). seeds.rb 의 시스템 유저와 동일 신원 규약.
    SYSTEM_USER_NAME = "시스템".freeze

    class << self
      def resolve(book:, surface:, user:, **deps)
        new(**deps).resolve(book: book, surface: surface, user: user)
      end

      def regenerate(book:, surface:, user:, **deps)
        new(**deps).regenerate(book: book, surface: surface, user: user)
      end

      # 다시 뽑기 per-user 스로틀 판정(M1). 한도 초과면 false → 컨트롤러가 새 버전 생성 없이 안내.
      def regenerate_allowed?(user, **deps)
        new(**deps).regenerate_allowed?(user)
      end

      def warm!(book, scope: nil, bands: ReadingDomain::BANDS, axes: nil, **deps)
        new(**deps).warm!(book, scope: scope, bands: bands, axes: axes)
      end

      def report!(quiz, **deps)
        new(**deps).report!(quiz)
      end

      # 로그인 불가한 시스템 액터(온디맨드 캐시 소유자)를 멱등 확보한다. 프로세스 내 메모이즈.
      # seeds.rb 와 같은 신원(name+school_id:nil+classroom_id:nil)이라 시드 유무와 무관하게 안전.
      def system_user
        User.find_or_create_by!(name: SYSTEM_USER_NAME, school_id: nil, classroom_id: nil) do |user|
          user.role = :superadmin
          user.password = SecureRandom.alphanumeric(24)
        end
      end

      # 문항 해시 배열(set)을 quiz 의 quiz_questions 로 빌드한다(오프라인 미스·워밍 게시 공용).
      def build_questions(quiz, set, source:)
        Array(set).each_with_index do |item, index|
          quiz.quiz_questions.build(question_attributes(item, index + 1, source))
        end
        quiz
      end

      # 균일 문항 해시 → QuizQuestion 컬럼 매핑. mcq 는 choices/answer_index 하위호환도 채운다.
      def question_attributes(item, position, source)
        {
          question_type: item[:question_type],
          prompt: item[:prompt],
          content: item[:content],
          answer: item[:answer],
          explanation: item[:explanation],
          difficulty: item[:difficulty],
          choices: item[:choices],
          answer_index: item[:answer_index],
          source: source,
          position: position
        }.compact
      end
    end

    def initialize(draft_service: Ai::QuizDraftService.new, rate_limiter: RateLimiter.new, client: Ai::GeminiClient.new)
      @draft_service = draft_service
      @rate_limiter = rate_limiter
      @client = client
    end

    def resolve(book:, surface:, user:)
      content_axis = SURFACE_MAP.fetch(surface.to_s) do
        raise ArgumentError, "지원하지 않는 surface: #{surface.inspect}"
      end
      band = ReadingDomain.band_for(user.classroom&.grade) # 서버 결정(사용자 입력 불신)

      cached = fetch_ready(book.id, band, content_axis)
      if cached
        maybe_retry_warming(book, band, content_axis, user, cached) # HIT → 즉시(Gemini 0) + (오프라인만 오래 지속 시) 재시도
        return cached
      end

      quiz = find_or_create_offline(book, band, content_axis) # MISS → 오프라인 즉시(무대기)
      maybe_enqueue_warming(book, band, content_axis, user)
      quiz
    end

    # 다시 뽑기(§3.4): 현재 캐시를 신고하지 않고 **새 content_version 오프라인 세트**를 즉시
    # 만들어 반환한다(fetch_ready 가 content_version desc 라 다음 resolve 는 이 최신 버전을 서빙).
    # 포인트는 PointAward 의 콘텐츠축(book×band×axis) 상한이 이미 봉인 — 재생성 후 만점을 다시 받아도
    # 이전 최고 적립액을 넘지 않으면 +0 이다(§3.4 "포인트는 최고 기록만 반영"). 예산/rate limit 하에
    # 워밍도 1건 재적재한다(무키/초과면 오프라인만). 콘텐츠 재생성이지 가챠·랜덤 획득이 아니다.
    def regenerate(book:, surface:, user:)
      content_axis = SURFACE_MAP.fetch(surface.to_s) do
        raise ArgumentError, "지원하지 않는 surface: #{surface.inspect}"
      end
      band = ReadingDomain.band_for(user.classroom&.grade)

      quiz = create_new_offline_version(book, band, content_axis)
      maybe_enqueue_warming(book, band, content_axis, user)
      quiz
    end

    # 다시 뽑기 per-user 스로틀(M1): 시간당 한도 내면 true. allow? 는 원자 increment 이므로 호출
    # 자체가 카운트를 올린다 — regenerate 요청 1회당 정확히 1회 호출할 것. 초과 시 컨트롤러가 새
    # content_version 생성을 건너뛰고 현재 캐시로 안내한다(무제한 DB 증식 차단, 무키·비AI 무관).
    def regenerate_allowed?(user)
      hour_bucket = Time.current.strftime("%Y%m%d%H")
      @rate_limiter.allow?("regenerate:user:#{user.id}:#{hour_bucket}", **REGENERATE_PER_USER)
    end

    # warm 사전생성(§3.5, A5): 카탈로그/과제 지정 도서를 첫 플레이 **전에** 워밍해 콜드-첫-오프라인
    # 노출(특히 matching/hint_reveal)을 최소화한다. band×content_axis 조합마다 워밍 잡을 1건씩
    # 적재하되, 스코프 플래그·rate limit/예산을 준수한다(무키면 아무 것도 적재하지 않음).
    # dedup(이미 워밍 중/AI 게시됨)은 GenerateGameContentJob 이 자체 가드한다. 적재한 잡 수를 반환.
    def warm!(book, scope: nil, bands: ReadingDomain::BANDS, axes: nil)
      return 0 unless @client.configured?

      axes ||= ReadingDomain::CONTENT_COUNTS.keys # mcq/matching/hint_reveal/balance_vote
      enqueued = 0
      bands.each do |band|
        axes.each do |axis|
          next unless warming_permitted?(scope, book.id, rate_limit_key: :warm_pregen)

          GenerateGameContentJob.perform_later(book.id, band.to_s, axis.to_s)
          enqueued += 1
        end
      end
      enqueued
    end

    # 신고 경로(§2b.3): 학생/교사 신고 → 캐시 행 숨김(reported) + 새 버전 재생성 트리거.
    # reported 행은 fetch_ready 에서 제외되어 다음 resolve 가 새 오프라인/워밍으로 대체한다.
    def report!(quiz)
      quiz.update!(reported: true)
      return quiz unless warming_permitted?(quiz.classroom, quiz.book_id)

      GenerateGameContentJob.perform_later(quiz.book_id, quiz.band, quiz.content_axis)
      quiz
    end

    private

    # 최신 준비완료 캐시 행(미신고). 오프라인 v1 도 ready 라 두 번째 resolve 부터는 여기서 HIT.
    def fetch_ready(book_id, band, content_axis)
      Quiz.where(origin: :system, generation_status: :ready, reported: false,
                 book_id: book_id, band: band, content_axis: content_axis)
          .order(content_version: :desc, id: :desc)
          .first
    end

    # 오프라인 결정적 system Quiz find-or-create. 최초 미스는 content_version=1 이며,
    # 신고(reported)로 v1 이 숨겨지면 다음 빈 버전으로 새 오프라인을 만들어 항상 **미신고·ready**
    # 행을 돌려준다(아동 무대기·무공백). thundering-herd 는 부분 유니크 인덱스가 잡고
    # (insert rescue RecordNotUnique) 승자 행을 재조회해 1생성을 보장한다.
    #
    # 재조회에서도 또 RecordNotUnique 가 날 수 있는 다중 동시 요청(2단계 이상 경쟁)을 대비해
    # OFFLINE_RACE_RETRY_LIMIT 만큼 유한 재시도한다(§2b 검증 후속 [LOW] — 무한 재귀/미보호 방지).
    def find_or_create_offline(book, band, content_axis)
      attempts = 0
      begin
        ready = fetch_ready(book.id, band, content_axis)
        return ready if ready

        persist_offline(book, band, content_axis)
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < OFFLINE_RACE_RETRY_LIMIT
        # 재시도 소진 — 누군가는 성공했을 것이므로 마지막으로 재조회, 그래도 없으면 원 예외를 전파.
        fetch_ready(book.id, band, content_axis) || raise
      end
    end

    # 재롤 전용: 캐시 유무와 무관하게 **항상 새 content_version** 오프라인 행을 만든다. 동시 재롤
    # 경쟁(RecordNotUnique)은 부분 유니크 인덱스가 잡고, 유한 재시도 후 승자 행을 재조회한다.
    def create_new_offline_version(book, band, content_axis)
      attempts = 0
      begin
        persist_offline(book, band, content_axis)
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < OFFLINE_RACE_RETRY_LIMIT
        fetch_ready(book.id, band, content_axis) || raise
      end
    end

    def persist_offline(book, band, content_axis)
      version = next_free_version(book.id, band, content_axis)
      build_offline_quiz(book, band, content_axis, version).tap(&:save!)
    end

    def next_free_version(book_id, band, content_axis)
      Quiz.where(origin: :system, book_id: book_id, band: band, content_axis: content_axis)
          .maximum(:content_version).to_i + 1
    end

    def build_offline_quiz(book, band, content_axis, version)
      quiz = Quiz.new(
        title: "온디맨드 #{content_axis}", created_by: self.class.system_user, book: book,
        scope: :global, published: true, origin: :system, content_axis: content_axis,
        band: band, content_version: version, generation_status: :ready
      )
      # MISS 즉시 반환 = 네트워크 0 결정적 오프라인(content_set 아님 — 아동 무대기 불변식).
      self.class.build_questions(quiz, @draft_service.offline_set(book, band, content_axis), source: :offline)
    end

    def maybe_enqueue_warming(book, band, content_axis, user)
      return unless @client.configured? # 무키 → 오프라인만, 잡 없음
      return unless warming_permitted?(user.classroom, book.id, rate_limit_key: user.id)

      GenerateGameContentJob.perform_later(book.id, band.to_s, content_axis.to_s)
    end

    # HIT 이지만 아직 AI 워밍이 반영되지 않은(오프라인만 있는) 축이 **영구** 오프라인에 갇히지
    # 않도록, 오프라인 세트가 충분히 오래됐다면(RETRY_GRACE 경과 — 정상 워밍 잡이라면 이미 끝났을
    # 시간) 예산/rate limit 하에 재워밍을 재시도한다(§2b 검증 후속 [LOW] — 단발성 moderation 거부나
    # 최초 미스 시 무키였던 경우가 영구 오프라인으로 굳지 않게 함). 막 만든 오프라인(정상 워밍이
    # 아직 진행 중일 수 있는 짧은 창)은 재시도하지 않아 N1(콘텐츠축당 1생성)을 어기지 않는다.
    # 축 단위 쿨다운(RETRY_COOLDOWN)으로 매 HIT 마다 재시도가 발동하는 낭비도 막는다.
    def maybe_retry_warming(book, band, content_axis, user, cached)
      return if cached.created_at > RETRY_GRACE.ago
      return if ai_backed?(cached)
      return unless @client.configured?
      return unless @rate_limiter.allow?(retry_cooldown_key(book, band, content_axis), limit: 1, period: RETRY_COOLDOWN)
      return unless warming_permitted?(user.classroom, book.id, rate_limit_key: user.id)

      GenerateGameContentJob.perform_later(book.id, band.to_s, content_axis.to_s)
    end

    # 캐시 행이 실제로 AI 로 게시된 적 있는지(질문 source==ai) — 없으면 "오프라인만" 인 축.
    def ai_backed?(quiz)
      quiz.quiz_questions.exists?(source: :ai)
    end

    def retry_cooldown_key(book, band, content_axis)
      "warm_retry:#{book.id}:#{band}:#{content_axis}"
    end

    # 워밍 허용 = 스코프 플래그 on AND rate limit/예산 OK. 초과 시 오프라인 강등(잡 미적재).
    def warming_permitted?(scope, _book_id, rate_limit_key: nil)
      return false unless AppSetting.feature_enabled?(FEATURE_FLAG, scope: scope)

      @rate_limiter.warming_allowed?(rate_limit_key || :global)
    end
  end
end
