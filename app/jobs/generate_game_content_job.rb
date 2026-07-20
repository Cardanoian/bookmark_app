# 온디맨드 게임 콘텐츠 백그라운드 워밍 잡(Phase 2b §2b.2). AiReviewJob/OcrJob 의
# 비동기 + 상태 전이 + Turbo 방송 패턴을 미러한다. ContentProvider 가 캐시 MISS 시
# 1건 적재하며, 아동은 이미 오프라인 세트로 플레이 중이므로 이 잡은 **비차단 승격**이다.
#
# perform(book_id, band, content_axis):
#   ① dedup 가드 — 같은 축에 **살아있는**(스테일 아닌) warming 행 또는 이미 AI 로 게시된
#      (quiz_questions.source == ai) ready 행이 있으면 조기 반환(thundering-herd·중복 워밍 방지).
#      "AI 로 게시됨"은 content_version≥2 로 근사하지 않는다 — 신고 후 오프라인 재생성도
#      버전이 올라가므로 버전만으로는 오판한다(§2b 검증 후속 [MEDIUM]).
#   ② warming system Quiz 선점 — 부분 유니크 인덱스로 동시 선점 1건만 성공(나머지 RecordNotUnique).
#      선점 전, 하드크래시로 고착된 스테일 warming 행(STALE_WARMING_AFTER 경과)은 리핑해 영구
#      차단을 막는다(§2b 검증 후속 [LOW] 스테일 리퍼).
#   ③ QuizDraftService#content_set 로 AI 세트 생성(무키/실패 시 내부적으로 오프라인 폴백).
#   ④ Ai::QuizModerator 게시 전 검증 — 통과분만 게시.
#   ⑤ 통과: quiz_questions 저장(source=ai) + ready 전이 + 비차단 Turbo 방송("새 문제 준비됐어요").
#      거부/실패: 게시하지 않고 warming 행 폐기(오프라인 유지) + moderation 거부 카운터 증가.
#      **방송 실패는 이미 커밋된 ready 게시를 되돌리지 않는다**(별도 rescue로 흡수, §2b 검증 후속 [LOW]).
class GenerateGameContentJob < ApplicationJob
  queue_as :default

  # 하드크래시(프로세스 강제 종료 등)로 rescue 가 못 도는 경우, warming 행이 영구 고착되어
  # 해당 콘텐츠축이 다시는 워밍되지 않는 사고를 막는다. 이 시간을 넘긴 warming 행은 스테일로
  # 간주해 리핑(폐기) 후 재선점을 허용한다.
  STALE_WARMING_AFTER = 10.minutes

  # 테스트 주입 훅 — 잡 인자는 직렬화되어 콜라보레이터 객체를 넘길 수 없으므로,
  # 구성된 스텁 클라이언트/모더레이터를 클래스 팩토리로 주입한다(운영은 기본 인스턴스).
  class << self
    attr_writer :draft_service_factory, :moderator_factory

    def draft_service_factory
      @draft_service_factory ||= -> { Ai::QuizDraftService.new }
    end

    def moderator_factory
      @moderator_factory ||= -> { Ai::QuizModerator.new }
    end

    # 테스트 teardown 에서 기본값으로 되돌린다.
    def reset_factories!
      @draft_service_factory = nil
      @moderator_factory = nil
    end
  end

  def perform(book_id, band, content_axis)
    book = Book.find_by(id: book_id)
    return unless book

    band = band.to_sym
    axis = content_axis.to_sym
    return if Games::CuratedContent.available?(book, axis) # 큐레이션 책은 스테일 워밍이 검수 문항을 ai 로 덮지 않게 조기 반환
    return if redundant?(book_id, band, axis) # dedup 가드

    quiz = claim_warming(book, band, axis)
    return unless quiz # 다른 잡이 선점 → 이 잡은 생성 포기(1생성 보장)

    set = draft_service.content_set(book, band, axis)
    moderation = moderator.review(set, content_axis: axis)

    if moderation.pass?
      publish!(quiz, set)
    else
      reject!(quiz, moderation.reasons)
    end
  rescue StandardError => e
    Rails.logger.error("GenerateGameContentJob failed for book #{book_id}/#{band}/#{content_axis}: #{e.class}: #{e.message}")
    # publish! 는 방송 실패를 내부에서 별도 rescue 로 흡수하므로 여기 도달하지 않는다 — 여기 도달했다면
    # 게시(생성·검증·트랜잭션)가 실패한 것이라 quiz 는 아직 warming(또는 미생성) 상태다. 이미 커밋된
    # ready 행을 실수로 지우지 않도록 DB 상태를 다시 확인한 뒤에만 폐기한다(§2b 검증 후속 [LOW]).
    destroy_if_still_warming(quiz)
  end

  private

  def draft_service
    self.class.draft_service_factory.call
  end

  def moderator
    self.class.moderator_factory.call
  end

  # warming 이 **진행 중**(스테일 아님)이거나 이미 **실제로 AI 로 게시된** ready 행이 있으면 중복.
  # reported 행은 이미 회수 대상이므로 두 판정 모두에서 제외한다(신고 후 재생성이 막히지 않게).
  def redundant?(book_id, band, axis)
    scope = Quiz.where(origin: :system, book_id: book_id, band: band, content_axis: axis, reported: false)
    active_warming?(scope) || ai_ready_exists?(scope)
  end

  # updated_at 이 STALE_WARMING_AFTER 이내인 warming 행만 "진행 중"으로 본다. 그보다 오래된 것은
  # 하드크래시로 고착된 스테일 행으로 간주해 여기서 차단하지 않는다(claim_warming 이 리핑한다).
  def active_warming?(scope)
    scope.where(generation_status: :warming).where("updated_at > ?", STALE_WARMING_AFTER.ago).exists?
  end

  # "AI 로 게시됨"은 content_version 크기가 아니라 **실제 문항 source** 로 판정한다.
  # content_version≥2 는 신고 후 재생성된 오프라인 행도 가질 수 있어(오판의 원인) count 부적절.
  def ai_ready_exists?(scope)
    scope.where(generation_status: :ready)
         .joins(:quiz_questions)
         .where(quiz_questions: { source: :ai })
         .exists?
  end

  # 다음 content_version 의 warming system Quiz 를 선점한다(문항은 게시 전까지 비어 있음).
  # 부분 유니크 인덱스가 (book,band,axis,version) 동시 선점을 1건으로 수렴시킨다. 선점 전
  # 스테일 warming 행을 리핑해, 하드크래시로 고착된 축도 다시 워밍될 수 있게 한다.
  def claim_warming(book, band, axis)
    reap_stale_warming!(book.id, band, axis)
    next_version = current_max_version(book.id, band, axis) + 1
    Quiz.create!(
      title: "온디맨드 #{axis} v#{next_version}", created_by: Games::ContentProvider.system_user,
      book: book, scope: :global, published: true, origin: :system, content_axis: axis,
      band: band, content_version: next_version, generation_status: :warming
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # STALE_WARMING_AFTER 를 넘긴 warming 행을 폐기한다(하드크래시로 rescue 가 못 돈 잔재 정리).
  def reap_stale_warming!(book_id, band, axis)
    Quiz.where(origin: :system, book_id: book_id, band: band, content_axis: axis, generation_status: :warming)
        .where("updated_at <= ?", STALE_WARMING_AFTER.ago)
        .destroy_all
  end

  def current_max_version(book_id, band, axis)
    Quiz.where(origin: :system, book_id: book_id, band: band, content_axis: axis)
        .maximum(:content_version).to_i
  end

  # 통과: 문항 게시(source=ai) + ready 전이(트랜잭션 커밋) 후 비차단 방송. content_version 은
  # 선점 시 이미 bump 됨. 방송은 별도 rescue 로 감싸 실패해도 **이미 커밋된 ready 게시를
  # 되돌리지 않는다**(로깅만, §2b 검증 후속 [LOW]) — 트랜잭션 자체의 실패는 여기서 흡수하지 않고
  # 그대로 전파해 perform 의 rescue 가 (아직 warming 인) quiz 를 정리하게 둔다.
  def publish!(quiz, set)
    quiz.transaction do
      Games::ContentProvider.build_questions(quiz, set, source: :ai)
      quiz.update!(generation_status: :ready)
    end

    begin
      broadcast_ready(quiz)
    rescue StandardError => e
      Rails.logger.error("GenerateGameContentJob broadcast failed for book #{quiz.book_id}/#{quiz.band}/#{quiz.content_axis}: #{e.class}: #{e.message}")
    end
  end

  # perform 의 rescue 전용 — 예외가 전파돼 여기 도달했을 때만 호출된다. DB 를 다시 확인해
  # **실제로 아직 warming** 인 경우에만 폐기한다(이미 삭제됐거나 ready 로 커밋됐으면 손대지 않음).
  def destroy_if_still_warming(quiz)
    return unless quiz

    quiz.reload.destroy if quiz.warming?
  rescue ActiveRecord::RecordNotFound
    # 이미 삭제됨(예: reject! 가 먼저 처리) — 할 일 없음.
  end

  # 거부: 게시하지 않고 warming 행 폐기(오프라인 유지) + 관측 카운터 증가.
  def reject!(quiz, reasons)
    Rails.logger.warn("QuizModerator rejected book #{quiz.book_id}/#{quiz.band}/#{quiz.content_axis}: #{reasons.join('; ')}")
    Rails.cache.increment("games:moderation_reject:#{quiz.content_axis}", 1)
    quiz.destroy
  end

  # 새 콘텐츠 준비 완료를 비차단으로 방송한다(플레이어는 이미 오프라인으로 플레이 중 → 승격 신호만).
  def broadcast_ready(quiz)
    Turbo::StreamsChannel.broadcast_append_to(
      [ quiz.book_id, quiz.band, quiz.content_axis, :game_content ],
      target: "game_content_status",
      html: "<span data-content-version=\"#{quiz.content_version}\">새 문제가 준비됐어요! 다시 뽑기로 만나 보세요.</span>"
    )
  end
end
