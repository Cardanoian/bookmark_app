# 독후감 첨삭 제출 버전(BUG_FIX_PLAN F2·F3) 운영 태스크.
#   reports:requeue_reviews       — 첨삭이 확정되지 않은 **현재 버전**을 같은 버전으로 다시 예약한다(§4.2-5·§4.4·§7.2).
#     큐 적재 실패로 누락됐거나, 배포 때 구형 큐 작업(버전 없음 — 기록만 남기고 종료된다)에 걸려 pending 으로
#     남은 글의 복구 절차다. 버전을 올리지 않으므로 검토 상태는 그대로고, 원래 작업이 늦게 끝나 겹쳐도
#     AiReviewJob 의 확정 조건이 결과·보상을 한 번만 반영한다. **이미 확정한 글은 다시 채점하지 않는다.**
#       기본 대상 : 제출된 글 중 대기(pending)·처리 중(processing)
#       FAILED=1  : 실패(failed)한 글도 포함한다 — 원인을 확인한 뒤에 선택적으로 쓴다.
#       APPLY=1   : 실제로 예약한다. 없으면 대상만 출력한다(dry-run).
#   reports:audit_review_versions — 읽기 전용 점검(§7.3). 승인(reviewed)됐는데 지금 제출의 첨삭이 완성되지 않은 글
#     (Report#review_ready? 거짓)을 목록화한다. 새 공개 조건이 이 글들의 첨삭을 학생에게 숨기므로, 재첨삭
#     (reports:requeue_reviews 또는 화면의 '첨삭 다시 요청')과 재승인이 필요한 대상이다. 아무것도 바꾸지 않는다.
# 출력에는 글 ID·버전·상태만 남긴다(학생 이름·본문은 출력하지 않는다).
namespace :reports do
  desc "첨삭이 확정되지 않은 현재 버전을 같은 버전으로 다시 예약(기본 dry-run, APPLY=1 로 실행, FAILED=1 로 실패 글 포함)"
  task requeue_reviews: :environment do
    statuses = %i[pending processing]
    statuses << :failed if ENV["FAILED"] == "1"
    apply = ENV["APPLY"] == "1"

    scope = Report.submitted.where(ai_status: statuses).where("review_version > 0")
                  .where("completed_review_version IS NULL OR completed_review_version <> review_version")
    puts "대상 #{scope.count}건 (상태: #{statuses.join(', ')})#{apply ? '' : ' — dry-run, 실제 예약은 APPLY=1'}"

    queued = 0
    scope.find_each do |report|
      puts "  report=#{report.id} version=#{report.review_version} completed=#{report.completed_review_version.inspect} status=#{report.ai_status}"
      next unless apply

      # 실패한 글은 pending 으로 되돌려 화면이 "첨삭 중"을 보이게 한다(같은 버전이 그사이 확정됐으면 0행).
      Report.where(id: report.id, review_version: report.review_version)
            .where("completed_review_version IS NULL OR completed_review_version <> review_version")
            .update_all(ai_status: Report.ai_statuses[:pending], updated_at: Time.current)
      queued += 1 if AiReviewJob.enqueue_for(report, report.review_version)
    end
    puts "예약 #{queued}건" if apply
  end

  desc "승인됐지만 지금 제출의 첨삭이 완성되지 않은 글을 목록화(읽기 전용)"
  task audit_review_versions: :environment do
    # 본문은 읽지 않는다(판정에 필요한 열만).
    columns = %i[id classroom_id submitted_at ai_status rubric review_version completed_review_version]
    rows = Report.where(reviewed: true).select(*columns).find_each.reject(&:review_ready?)
    puts "승인됐지만 review_ready? 가 아닌 글 #{rows.size}건 (첨삭은 학생에게 보이지 않는다 — 재첨삭·재승인 대상)"
    rows.each do |report|
      puts "  report=#{report.id} classroom=#{report.classroom_id} submitted=#{report.submitted?} status=#{report.ai_status} " \
           "rubric=#{report.rubric.present?} version=#{report.review_version} completed=#{report.completed_review_version.inspect}"
    end

    # 제출됐는데 버전이 0 인 글은 어떤 경로로도 첨삭·승인되지 않는다(정상 흐름에서는 생기지 않는다 — 제출은
    # 항상 Report#record_submission! 이 버전과 함께 기록한다). 수동 이관 흔적이면 버전을 1 로 바로잡은 뒤 재예약한다.
    unversioned = Report.submitted.where(review_version: 0).pluck(:id)
    puts "제출됐는데 제출 버전이 0 인 글 #{unversioned.size}건#{unversioned.any? ? " — report=#{unversioned.join(', ')}" : ''}"
  end
end
