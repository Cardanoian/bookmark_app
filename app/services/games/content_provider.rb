module Games
  # 콘텐츠축 캐시-우선 리졸버(Phase 2b §2b.1). 학생이 어떤 표면(surface)으로 게임에 진입하든
  # 표면을 **콘텐츠축(content_axis)** 으로 접어(N1) 캐시를 조회하고, 없으면 **책 파생 결정적
  # 오프라인 system Quiz 를 즉시 만들어 반환**한다. 아동은 **결코 대기하지 않는다** —
  # generation_status 는 플레이어에게 노출되지 않는 내부 캐시 상태일 뿐, 게이트가 아니다.
  #
  # 흐름(resolve):
  #   ① surface → content_axis (SURFACE_MAP; quiz→mcq·whoami→hint_reveal, 콘텐츠축당 1생성).
  #   ② band = ReadingDomain.game_band_for(user.classroom&.grade) — **서버 결정**(사용자 입력 불신).
  #      게임 전용 밴드(학년 미상 → 최저 g12; 5~6학년 기본 매칭 금지). 정책(QuizPolicy#within_band?)과 동일.
  #   ③ 캐시 HIT: origin=system·해당 축·최신 content_version·ready·미신고 → 즉시 반환(Claude 0).
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
  #    content_set 은 키가 있으면 동기 Claude 호출로 아동을 대기시키므로 "미스=오프라인 즉시"
  #    불변식(A.1 P1)에 위배된다. AI 는 오직 워밍 잡에서만 붙는다.
  class ContentProvider
    # 표면 → 콘텐츠축(게임 재구성 Phase 1). classic(→quiz 통합)·vocab(matching, hard-delete) 표면 제거.
    SURFACE_MAP = {
      "quiz" => :mcq,
      "whoami" => :hint_reveal
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

    # 신고 자동 숨김 임계(무게이트 롤아웃 안전장치, TODO 후속 정밀화). **서로 다른** 신고자가 이 수에
    # 도달하면 캐시 행을 숨기고 재생성한다. 단일 사용자 연타 악용은 quiz_reports 의 (quiz, user)
    # 유니크(1인 1신고)로 이미 차단되므로, 이 값은 곧 "서로 다른 신고자 수" 임계다. 운영 튜닝은 TODO 참조.
    REPORT_HIDE_THRESHOLD = 2

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

      # 가용성 게이트(Phase 4 §2a). (book, band, content_axis)에 **진짜** 게임 콘텐츠를 만들 수
      # 있는지 판정한다 — true 인 게임만 표시·플레이하고, false 면 "일반 문제로 때우지 않고 비활성".
      def game_content_available?(book:, content_axis:, user:, **deps)
        new(**deps).game_content_available?(book: book, content_axis: content_axis, user: user)
      end

      def warm!(book, scope: nil, bands: ReadingDomain::BANDS, axes: nil, **deps)
        new(**deps).warm!(book, scope: scope, bands: bands, axes: axes)
      end

      def report!(quiz, **deps)
        new(**deps).report!(quiz)
      end

      def record_report!(quiz, reporter, **deps)
        new(**deps).record_report!(quiz, reporter)
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

    # sampler: 준비된 후보 세트들(배열) 중 하나를 고르는 seam(Phase 3 문제은행 §3.5). 기본은 균등 랜덤
    # (`.sample`)이라 (책·밴드·축)에 여러 세트(오프라인·AI·기여)가 쌓이면 **매 플레이마다 다른 세트가
    # 출제**된다(세트 단위 랜덤 출제). 테스트는 결정적 sampler(예: `->(c){ c.first }`)를 주입해 검증한다.
    def initialize(draft_service: Ai::QuizDraftService.new, rate_limiter: RateLimiter.new, client: Ai::ClaudeClient.new,
                   sampler: ->(candidates) { candidates.sample })
      @draft_service = draft_service
      @rate_limiter = rate_limiter
      @client = client
      @sampler = sampler
    end

    def resolve(book:, surface:, user:)
      content_axis = SURFACE_MAP.fetch(surface.to_s) do
        raise ArgumentError, "지원하지 않는 surface: #{surface.inspect}"
      end
      band = ReadingDomain.game_band_for(user.classroom&.grade) # 서버 결정(게임 밴드, 학년 미상→g12)

      cached = fetch_ready(book.id, band, content_axis)
      if cached
        maybe_retry_warming(book, band, content_axis, user, cached) # HIT → 즉시(Claude 0) + (오프라인만 오래 지속 시) 재시도
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
      band = ReadingDomain.game_band_for(user.classroom&.grade)

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

    # 가용성 판정. 검수된 시드 또는 실제 내용으로 게시된 콘텐츠가 있을 때만 게임을 연다.
    # summary 만으로 만든 오프라인 폴백은 제목·지은이·낱말 맞히기 같은 샘플 문제가 될 수 있으므로,
    # 콘텐츠가 없을 때 일반 문제로 대신 출제하지 않고 비활성으로 둔다.
    # band 는 현재 학생 기준(game_band_for)으로 판정한다(QuizPolicy#within_band? 와 동일 함수).
    def game_content_available?(book:, content_axis:, user:)
      return true if Games::CuratedContent.available?(book, content_axis) # 큐레이션 검수 문항이 있으면 항상 가용

      band = ReadingDomain.game_band_for(user.classroom&.grade)
      substantive_content_exists?(book.id, band, content_axis.to_sym)
    end

    # warm 사전생성(§3.5, A5): 카탈로그/과제 지정 도서를 첫 플레이 **전에** 워밍해 콜드-첫-오프라인
    # 노출(특히 hint_reveal)을 최소화한다(게임 재구성 Phase 1: matching 생성 경로 제거로 mcq·hint_reveal
    # 만 대상). band×content_axis 조합마다 워밍 잡을 1건씩 적재하되, 스코프 플래그·rate limit/예산을
    # 준수한다(무키면 아무 것도 적재하지 않음).
    # dedup(이미 워밍 중/AI 게시됨)은 GenerateGameContentJob 이 자체 가드한다. 적재한 잡 수를 반환.
    def warm!(book, scope: nil, bands: ReadingDomain::BANDS, axes: nil)
      return 0 unless @client.configured?

      axes ||= ReadingDomain::CONTENT_COUNTS.keys # mcq/hint_reveal
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

    # 신고 접수(무게이트 롤아웃 안전장치): 신고자를 **1인 1신고**로 기록하고(중복은 무시),
    # **서로 다른** 신고자가 REPORT_HIDE_THRESHOLD 에 도달하면 report!(숨김+재생성)를 태운다.
    # 반환 해시 { created:, hidden: } 로 컨트롤러가 정직한 안내를 만들고, 접수는 신고자 학급
    # 담임의 대시보드 "신고된 콘텐츠" 섹션으로 사후 검토된다(교사 알림). 이미 숨김 처리된 행이면
    # 3번째 이후 신고에서 재숨김/재재생성을 걸지 않는다.
    def record_report!(quiz, reporter)
      created =
        begin
          quiz.quiz_reports.create!(user: reporter)
          true
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          false # 이미 신고한 사용자 — 카운트 중복 금지(1인 1신고)
        end

      hidden = false
      if created && !quiz.reported? && quiz.reload.reports_count >= REPORT_HIDE_THRESHOLD
        report!(quiz)
        hidden = true
      end

      { created: created, hidden: hidden }
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

    # 준비완료 캐시 세트(미신고) 중 하나를 서빙한다(문제은행식 세트 단위 랜덤 출제, Phase 3 §3.5).
    # 오프라인 v1 도 ready 라 두 번째 resolve 부터는 여기서 HIT. (책·밴드·축)에 오프라인·AI 워밍·학생
    # 승인 기여 세트가 여러 개 쌓이면 sampler(기본 균등 랜덤)가 **매 플레이마다 다른 세트를 고른다** —
    # 아동 대면 채점 파이프라인(_quiz_form·attempts·QuizPlay)은 여전히 quiz_id 로 그 한 세트를 통째
    # 제출·채점하므로 무변경이다(세트 단위 랜덤일 뿐 문항 단위 샘플링이 아님). content_version desc 정렬은
    # 결정적 sampler(테스트)가 "최신"을 고를 수 있게 유지한다.
    #
    # ⚠️ maybe_retry_warming 은 이 랜덤 선택 결과(cached)를 그대로 판정 대상으로 받는다 — offline-only·
    #   ai-backed 세트가 풀에 공존할 때 드물게 offline-only 를 뽑으면 이미 AI 콘텐츠가 있는 축에도
    #   재워밍이 걸릴 수 있다(correctness 회귀 아님, RETRY_COOLDOWN·예산으로 상한된 소량 비효율 — 상세는
    #   maybe_retry_warming 주석).
    #
    # ⚠️ 가용성 게이트: 컨트롤러/뷰는 검수 시드 또는 승인 기여가 없는 책을 resolve 전에 막는다.
    #   따라서 여기의 자동 생성 폴백은 직접 서비스 호출의 호환성만 위한 것이며, 일반 게임 화면에는
    #   노출되지 않는다.
    def fetch_ready(book_id, band, content_axis)
      base = Quiz.where(origin: :system, generation_status: :ready, reported: false,
                        book_id: book_id, band: band, content_axis: content_axis)
      # 큐레이션(검수) 세트가 있으면 그 풀만 서빙해 제네릭 오프라인/미검증 ai 세트로 덮이지 않게 한다.
      curated = base.joins(:quiz_questions).where(quiz_questions: { source: :curated })
                    .distinct.order(content_version: :desc, id: :desc).to_a
      candidates = curated.presence || base.order(content_version: :desc, id: :desc).to_a
      return nil if candidates.empty?

      @sampler.call(candidates)
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
      # 큐레이션 우선: 검수 문항이 있는 책은 밴드별로 이 경로에서 지연 물질화된다(밴드 팬아웃 자동 처리).
      # 없으면 MISS 즉시 반환 = 네트워크 0 결정적 오프라인(content_set 아님 — 아동 무대기 불변식).
      curated = Games::CuratedContent.set_for(book, content_axis)
      if curated
        self.class.build_questions(quiz, curated, source: :curated)
      else
        self.class.build_questions(quiz, @draft_service.offline_set(book, band, content_axis), source: :offline)
      end
    end

    def maybe_enqueue_warming(book, band, content_axis, user)
      return if Games::CuratedContent.available?(book, content_axis) # 큐레이션 책은 AI 워밍 억제(미검증 ai 재유입 차단)
      return unless @client.configured? # 무키 → 오프라인만, 잡 없음
      return unless warming_permitted?(user.classroom, book.id, rate_limit_key: user.id)

      GenerateGameContentJob.perform_later(book.id, band.to_s, content_axis.to_s)
      maybe_enqueue_book_summary(book) # Phase 4 §1d — 줄거리 미확인 책이면 함께 1회 큐잉(워밍 예산 하)
    end

    # Phase 4 §1d 온디맨드 트리거. 워밍이 도는 시점(키 있음·예산 OK)에, 그 책이 아직 줄거리도
    # 없고 Claude 확인도 안 했으면 BookSummaryJob 을 함께 1회 큐잉한다(멱등·throttle 이라 중복 안전).
    # 무키에서는 maybe_enqueue_warming 이 먼저 return 하므로 이 경로도 안 걸린다.
    #
    # ⚠️ 도달 범위(code-review 후속): 이 경로는 **`resolve` 가 실제로 호출된 책에만** 도달한다 —
    #   `Games::BaseController#content_gate_allows?`(§2c)가 **비활성 책은 resolve 전에 리다이렉트**
    #   시키므로, AI-부적격이고 기여/AI 콘텐츠도 없는 책은 여기 트리거가 절대 걸리지 않는다(영원히
    #   미확인으로 고착되는 것을 막기 위한 부트스트랩은 이 메서드의 책임이 아니다). 비활성 책의
    #   Claude 확인 부트스트랩은 ① `ReadingActivitiesController#bootstrap_book_summary`(학생이 책을
    #   선택하는 게이트 우회 지점, 온디맨드) ② `Recommendations::Importer`(신규 유입, BookEnrichmentJob
    #   미러) ③ `games:backfill_book_summaries` rake(벌크)가 담당한다. 여기 트리거는 **이미 가용한**
    #   책(고전·기여/AI 콘텐츠 보유)이 재생 중에 줄거리까지 채워지는 부가 경로일 뿐이다.
    def maybe_enqueue_book_summary(book)
      return unless book.summary.blank? && book.summary_checked_at.nil?

      BookSummaryJob.perform_later(book.id)
    end

    # 그 (book, band, content_axis)에 검수 시드 또는 승인 기여로 물질화된 ready·미신고 system
    # 세트가 하나라도 있는지. 자동 생성(ai·offline) 캐시는 검수 전이므로 가용 근거로 쓰지 않는다.
    def substantive_content_exists?(book_id, band, content_axis)
      Quiz.where(origin: :system, generation_status: :ready, reported: false,
                 book_id: book_id, band: band, content_axis: content_axis)
          .joins(:quiz_questions)
          .where(quiz_questions: { source: [ :contributed, :curated ] })
          .exists?
    end

    # HIT 이지만 아직 AI 워밍이 반영되지 않은(오프라인만 있는) 축이 **영구** 오프라인에 갇히지
    # 않도록, 오프라인 세트가 충분히 오래됐다면(RETRY_GRACE 경과 — 정상 워밍 잡이라면 이미 끝났을
    # 시간) 예산/rate limit 하에 재워밍을 재시도한다(§2b 검증 후속 [LOW] — 단발성 moderation 거부나
    # 최초 미스 시 무키였던 경우가 영구 오프라인으로 굳지 않게 함). 막 만든 오프라인(정상 워밍이
    # 아직 진행 중일 수 있는 짧은 창)은 재시도하지 않아 N1(콘텐츠축당 1생성)을 어기지 않는다.
    # 축 단위 쿨다운(RETRY_COOLDOWN)으로 매 HIT 마다 재시도가 발동하는 낭비도 막는다.
    #
    # ⚠️ Phase 3 세트 단위 랜덤(§3.5)과의 상호작용: 판정 대상 `cached` 는 **이번에 sampler 가 고른
    #   그 세트**다. 풀에 offline-only 세트와 ai-backed 세트가 **공존**할 때 sampler 가 우연히 오래된
    #   offline-only 세트를 고르면, 그 축에 이미 AI 콘텐츠가 있음에도 재워밍이 걸릴 수 있다(다음
    #   HIT 에서 ai-backed 세트를 고르면 안 걸림 — 순전히 이번 판이 어떤 세트를 뽑았는지에 달림).
    #   이는 **정확성 회귀가 아니다**(잘못된 콘텐츠가 나가지 않음) — 축 단위 쿨다운(RETRY_COOLDOWN,
    #   1시간 1회)·예산/rate limit 이 상한을 걸어 **드물게 소량의 불필요한 워밍 잡**만 발생할 수 있다.
    def maybe_retry_warming(book, band, content_axis, user, cached)
      return if Games::CuratedContent.available?(book, content_axis) # 큐레이션 책은 AI 워밍 억제(미검증 ai 재유입 차단)
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
