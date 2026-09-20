# 독후감 제출 → 비동기 5축 첨삭. **작업이 시작한 제출 버전과 현재 제출 버전이 같을 때만** 결과를 반영하고,
# 같은 버전의 결과와 포인트는 한 번만 확정한다(BUG_FIX_PLAN F2 §4.3). (§9.4, P3.6)
#
# 세 구간으로 나눈다. 외부 AI 호출(②)은 오래 걸리므로 DB 트랜잭션 밖에서 하고 — SQLite 는 쓰기 잠금이 DB
# 전체에 걸린다 — 그사이 학생이 고쳐 다시 냈을 수 있으니 ③에서 버전을 다시 확인한다.
#   ① 시작 확인(짧은 트랜잭션)  : 버전·제출 여부·미완료 확인 + processing 기록 + 입력 스냅샷
#   ② 첨삭 생성(트랜잭션 밖)    : 스냅샷으로 Ai::ReviewService(외부 AI 또는 규칙 기반 폴백)
#   ③ 결과 확정(짧은 트랜잭션)  : 조건부 UPDATE 로 확정 권한 확인 → 루브릭·등급·지급 기록·포인트를 함께 반영
#
# 예전에는 버전이 없어 늦게 끝난 이전 작업이 새 본문에 이전 첨삭을 덮어썼고, 차액의 기준인 points_awarded 를
# 작업이 시작할 때 읽어 둔 값으로 써서 겹쳐 돈 작업이 저마다 전액을 적립했다(글에는 마지막 값만 남았다).
class AiReviewJob < ApplicationJob
  queue_as :default

  # 학생이 첨삭 대기 중인 독후감을 삭제했다면 남은 큐 작업은 실패로 쌓지 않는다.
  discard_on ActiveJob::DeserializationError

  # ①에서 확보해 ②·③이 쓰는 입력. report 는 그 순간 읽은 행(본문·도서·학급을 미리 불러 둔 것 — 이후
  # 다시 읽지 않는다), weights 는 그 순간의 학급 채점 가중치(예전 apply_rubric! 는 저장 시점에 다시 읽었다).
  Snapshot = Data.define(:report, :weights)

  # 예약은 이 메서드로만 한다 — 버전을 빠뜨리지 않게. 제출 커밋이 끝난 뒤에 부른다(커밋 전에 잡이 돌면
  # 제출 전 상태를 읽는다). primary DB 와 queue DB 는 따로라 제출 커밋과 큐 적재는 한 원자 작업이 아니다 —
  # 적재가 실패해도 이미 커밋된 제출을 500 으로 만들지 않고 기록만 남긴다. 그 글은 pending 으로 남아
  # Report#review_retryable? 가 참이 되고, 같은 버전 재예약(화면의 '첨삭 다시 요청'·reports:requeue_reviews)으로 복구한다.
  # 반환: 적재했으면 true.
  def self.enqueue_for(report, version)
    # 제출 버전은 1 부터다. 0 이하로는 예약하지 않는다(perform 도 같은 가드 — 0 으로 확정하면 승인도 재요청도 못 한다).
    unless version.to_i.positive?
      Rails.logger.error("AiReviewJob enqueue refused report=#{report.id} version=#{version.inspect}: not a submitted version")
      return false
    end

    perform_later(report, expected_review_version: version)
    true
  rescue StandardError => e
    Rails.logger.error("AiReviewJob enqueue failed report=#{report.id} version=#{version}: #{e.class}: #{e.message}")
    false
  end

  def perform(report, expected_review_version: nil)
    version = expected_review_version
    # 버전 없는 작업 = 이 수정 이전 형식으로 큐에 남아 있던 작업(§7.2). 현재 버전을 임의로 붙여 돌리지 않는다.
    return log_outcome(report, version, :skipped_legacy_job_without_version) if version.nil?
    # 제출 버전은 1 부터다(초안은 0). 0 이하로 확정하면 review_ready?(버전 > 0)가 영영 거짓이라 승인도 재요청도
    # 못 하는 글이 된다 — 수동 이관 등으로 "제출됐는데 버전 0"인 행이 생겨도 여기서 멈춘다(reports:audit 이 목록화).
    return log_outcome(report, version, :skipped_invalid_version) unless version.to_i.positive?

    snapshot = begin_review(report, version)
    return unless snapshot

    review = Ai::ReviewService.new.call(snapshot.report)
    outcome = finalize_review(report.id, version, snapshot, review)
    log_outcome(report, version, outcome[:status])
    run_after_commit_effects(outcome) if outcome[:status] == :completed
  rescue StandardError => e
    # 학생 본문·AI 응답 전문은 남기지 않는다(글 ID·버전·예외만).
    Rails.logger.error("AiReviewJob failed report=#{report&.id} version=#{version}: #{e.class}: #{e.message}")
    mark_failed(report, version)
  end

  private

  # ① 시작 확인. 지금 버전의 **제출된·아직 확정되지 않은** 글일 때만 processing 을 기록하고 스냅샷을 돌려준다.
  # 이전 버전·삭제된 글·초안·이미 확정된 같은 버전이면 아무것도 바꾸지 않고 nil.
  # processing 인 행도 다시 시작할 수 있다 — 워커가 처리 중에 죽어도 재시도가 영구히 막히지 않는다.
  # (같은 버전이 겹쳐 돌면 외부 호출이 중복될 수 있지만, 결과와 보상의 한 번 반영을 먼저 보장한다 — ③.)
  def begin_review(report, version)
    Report.transaction do
      started = Report.where(id: report.id, review_version: version).where.not(submitted_at: nil)
                      .where("completed_review_version IS NULL OR completed_review_version <> ?", version)
                      .update_all(ai_status: Report.ai_statuses[:processing], updated_at: Time.current)
      unless started == 1
        log_outcome(report, version, :skipped_not_current)
        next nil
      end

      fresh = Report.includes(:book, :user, :classroom).find(report.id)
      Snapshot.new(report: fresh,
                   weights: fresh.classroom&.rubric_weights || ReadingDomain::DEFAULT_RUBRIC_WEIGHTS)
    end
  end

  # ③ 결과 확정. 다시 읽은 현재 버전이 작업 버전과 같고 아직 확정되지 않았을 때만, 조건부 UPDATE 로 확정
  # 권한을 잡는다(영향 행 1 — 같은 버전의 중복 작업 중 하나만 통과). 그 뒤 루브릭·평균·등급·개선도·지급 기록과
  # 포인트·경험치·시즌 점수를 **같은 트랜잭션**에서 반영한다 — 예외가 나면 결과와 지급이 함께 롤백된다.
  # 차액은 이 안에서 다시 읽은 points_awarded 로 계산한다(멱등 포인트: 재첨삭 파밍 차단).
  def finalize_review(report_id, version, snapshot, review)
    Report.transaction do
      claimed = Report.where(id: report_id, review_version: version).where.not(submitted_at: nil)
                      .where("completed_review_version IS NULL OR completed_review_version <> ?", version)
                      .update_all(completed_review_version: version)
      next { status: :skipped_stale_or_completed } unless claimed == 1

      report = Report.find(report_id)
      result = RubricScorable.score_rubric(review[:rubric], weights: snapshot.weights)
      report.rubric = review[:rubric].merge(praise: review[:praise], fix: review[:fix], grow: review[:grow])
      report.avg = result[:avg]
      report.level = result[:level]
      report.improvement = (report.avg - report.prev_avg).round(2) if report.revision_of_id? && report.prev_avg.present?

      delta = result[:points].to_i - report.points_awarded.to_i
      report.points_awarded = result[:points].to_i
      report.ai_status = :done
      # 방금 확정한 첨삭은 아직 아무도 확인하지 않았다. 정상 흐름에서는 이미 미승인이지만(제출이 승인을 풀고,
      # 승인은 확정된 버전에만 된다), 이 규칙 이전에 "첨삭 없이 승인"된 글을 같은 버전으로 다시 첨삭했을 때
      # 교사가 읽지 않은 결과가 곧바로 공개되지 않게 여기서 못박는다(§7.3 — 재첨삭 뒤에는 재승인).
      report.reviewed = false
      report.reviewed_at = nil
      report.save!

      # 트랜잭션 안에서는 원자 프리미티브만 쓴다(award_points 는 reload·후크·방송을 함께 해 롤백에 오염된다).
      if delta.positive?
        report.user.credit_points!(delta)
      elsif delta.negative?
        report.user.revoke_points!(delta.abs)
      end

      { status: :completed, report: report, delta: delta }
    end
  end

  # 커밋 뒤의 후크·방송. 여기서 나는 예외는 이미 확정한 결과를 실패로 바꾸지 않고, 보상을 다시 지급하게
  # 하지도 않는다(perform 의 rescue 로 올리지 않는다).
  #
  # 음수 델타에서 check_evolution! 을 부르지 않는 이유(#misc, 의도된 정책):
  #   ① 진화는 단조(monotonic)다 — 몬스터는 조건 충족 시 전진(evolve!)만 하고 역진화가 없다.
  #      포인트가 줄어도 이미 진화한 폼은 되돌아가지 않으므로 재평가할 상태 변화가 없다.
  #   ② check_evolution! 은 부작용 없는 순수 술어(active_monster&.evolvable?)라, 음수 델타에서
  #      호출해도 "진화 가능" 힌트 표시만 최신화될 뿐 데이터는 바뀌지 않는다 → 스킵이 안전하다.
  #   반면 refresh_badges! 는 유지한다(최신 포인트 기준 뱃지 상태 재계산).
  def run_after_commit_effects(outcome)
    report = outcome[:report]
    user = report.user
    if outcome[:delta].positive?
      user.run_point_side_effects! # 뱃지·진화·랭킹 방송
    elsif outcome[:delta].negative?
      user.reload
      user.refresh_badges!
    end

    broadcast_review_ready(report)
    report.broadcast_detail_refresh
  rescue StandardError => e
    Rails.logger.error("AiReviewJob after-commit effects failed report=#{report&.id}: #{e.class}: #{e.message}")
  end

  # 실패 기록. **이 작업의 버전이 아직 현재 버전이고 확정되지 않았을 때만** failed 로 바꾼다 — 이전 버전
  # 작업의 실패가 최신 제출을 failed 로 만들지 않고, 같은 버전의 다른 작업이 이미 성공했다면 뒤늦은 실패도
  # 무시한다(승인까지 끝난 글이 실패로 뒤집히지 않는다).
  def mark_failed(report, version)
    return if report.nil? || version.nil?

    failed = Report.where(id: report.id, review_version: version)
                   .where("completed_review_version IS NULL OR completed_review_version <> ?", version)
                   .update_all(ai_status: Report.ai_statuses[:failed], updated_at: Time.current)
    log_outcome(report, version, failed == 1 ? :failed : :failure_ignored_not_current)
    Report.find_by(id: report.id)&.broadcast_detail_refresh if failed == 1
  rescue StandardError => e
    Rails.logger.error("AiReviewJob could not record failure report=#{report&.id} version=#{version}: #{e.class}: #{e.message}")
  end

  # 첨삭 완료 → 교사 검토 목록에 행을 추가한다(제출→검토 목록 실시간, §10, P3.9).
  # **최신 DB 상태를 다시 확인한다** — 방송하려는 순간 이미 승인됐거나 학생이 다시 냈다면 오래된 검토 행을
  # 덧붙이지 않는다(행 파셜도 같은 상태 판정으로 승인 컨트롤을 렌더한다).
  # 스트림·타깃 이름 `review_queue` 는 방송·구독·테스트가 결합된 내부 식별자라 그대로 둔다.
  def broadcast_review_ready(report)
    report.reload
    return unless report.review_ready? && !report.reviewed?

    report.broadcast_append_to(
      [ report.classroom, :review_queue ],
      target: "review_queue",
      partial: "teacher/reviews/report_row",
      locals: { report: report }
    )
  end

  # 글 ID·작업 버전·현재 버전·처리 결과만 남긴다. 학생 본문과 AI 응답 전문은 남기지 않는다.
  def log_outcome(report, version, status)
    current = Report.where(id: report&.id).pick(:review_version)
    Rails.logger.info("AiReviewJob report=#{report&.id} job_version=#{version.inspect} current_version=#{current.inspect} outcome=#{status}")
  end
end
