# 독후감 제출 → 비동기 5축 첨삭. ai_status 를 processing→done 으로 전이시키고
# 등급·포인트·유사도를 저장한다. 실패 시 :failed. (§9.4, P3.6)
class AiReviewJob < ApplicationJob
  queue_as :default

  # 학생이 첨삭 대기 중인 독후감을 삭제했다면 남은 큐 작업은 실패로 쌓지 않는다.
  discard_on ActiveJob::DeserializationError

  def perform(report)
    report.update!(ai_status: :processing)

    review = Ai::ReviewService.new.call(report)
    result = report.apply_rubric!(review[:rubric])
    report.rubric = review[:rubric].merge(
      praise: review[:praise],
      fix: review[:fix],
      grow: review[:grow]
    )
    report.improvement = (report.avg - report.prev_avg).round(2) if report.revision_of_id? && report.prev_avg.present?

    # 멱등 포인트: 이 독후감이 이미 지급한 것과의 차액만 반영해 재첨삭 파밍을 막는다.
    previously_awarded = report.points_awarded.to_i
    delta = result[:points].to_i - previously_awarded
    report.points_awarded = result[:points].to_i
    report.ai_status = :done
    report.save!

    award_points_delta(report.user, delta)
    broadcast_review_ready(report)
    report.broadcast_detail_refresh
  rescue StandardError => e
    Rails.logger.error("AiReviewJob failed for report #{report&.id}: #{e.class}: #{e.message}")
    if report&.update(ai_status: :failed)
      report.broadcast_detail_refresh
    end
  end

  private

  # 포인트 차액 적용. 양수는 award_points 로 포인트·경험치를 함께 적립해 뱃지·진화·랭킹
  # 후크를 태우고, 음수(재첨삭으로 등급 하락)는 그 보상에서 생긴 포인트·경험치를 함께
  # 정정한 뒤 뱃지를 재계산(멱등)한다. 일반 포인트 소비와 달리 지급 원인 자체의 정정이므로
  # 경험치도 회수해야 재첨삭 등급 등락으로 경험치를 반복 적립하는 허점이 생기지 않는다.
  #
  # 음수 델타에서 check_evolution! 을 재호출하지 않는 이유(#misc, 의도된 정책):
  #   ① 진화는 단조(monotonic)다 — 몬스터는 조건 충족 시 전진(evolve!)만 하고 역진화가 없다.
  #      포인트가 줄어도 이미 진화한 폼은 되돌아가지 않으므로 재평가할 상태 변화가 없다.
  #   ② check_evolution! 은 부작용 없는 순수 술어(active_monster&.evolvable?)라, 음수 델타에서
  #      호출해도 "진화 가능" 힌트 표시만 최신화될 뿐 데이터는 바뀌지 않는다 → 스킵이 안전하다.
  #   반면 refresh_badges! 는 유지한다(최신 포인트 기준 뱃지 상태 재계산). 멱등 델타 패턴은 보존한다.
  def award_points_delta(user, delta)
    if delta.positive?
      # award_points 가 원자 증가(update_counters)+reload+후크를 담당 — 여기서 이중 적용하지 않는다.
      user.award_points(delta, reason: "report_review")
    elsif delta.negative?
      # 음수 델타는 0 바닥의 원자 정정으로 비원자 read-modify-write 경합을 없앤다.
      # (포인트 임계 뱃지 조건은 없어 refresh_badges! 전 reload 는 필수는 아니나, 최신값 기준으로 재계산하도록 유지.)
      user.revoke_points!(delta.abs)
      user.reload
      user.refresh_badges!
    end
  end

  # 첨삭 완료 → 교사 검토 목록에 행을 추가한다(제출→검토 목록 실시간, §10, P3.9).
  # 스트림·타깃 이름 `review_queue` 는 방송·구독·테스트가 결합된 내부 식별자라 그대로 둔다.
  def broadcast_review_ready(report)
    report.broadcast_append_to(
      [ report.classroom, :review_queue ],
      target: "review_queue",
      partial: "teacher/reviews/report_row",
      locals: { report: report }
    )
  end
end
