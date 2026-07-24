# 미션 재설계 데이터 전환 태스크(menu_refactor 심화 §2.B.2·§2.B.3).
#   missions:backfill_legacy — 레거시 참여(reports.mission_id) → 완료 MissionParticipation 백필(멱등).
#     ReadingStats#missions 를 completed_at 기준으로 전환(PR2)해도 몬스터 조건(missions 지표 의존
#     bear·squirrel·robot·dino·dokkaebi 라인)이 퇴행하지 않도록, 레거시 참여를 "0P 완료" 원장으로
#     보존한다. 재실행 안전(find_or_initialize + ||= + 완료행 skip).
#   missions:verify_backfill — 학생별 old(reports distinct mission_id) vs new(완료 participation) 대조.
#     mismatch 0 이 reader 전환(PR2) 배포 게이트다.
namespace :missions do
  desc "레거시 참여(reports.mission_id) → 완료 MissionParticipation 백필(멱등)"
  task backfill_legacy: :environment do
    created = 0
    skipped = 0

    # [mission_id, user_id] => 최초 연결 report 시각
    rows = Report.where.not(mission_id: nil)
                 .group(:mission_id, :user_id)
                 .minimum(:created_at)

    rows.each do |(mission_id, user_id), first_at|
      participation = MissionParticipation.find_or_initialize_by(mission_id: mission_id, user_id: user_id)

      # 실제 완료 원장은 덮어쓰지 않는다(멱등·안전).
      if participation.persisted? && participation.completed_at.present?
        skipped += 1
        next
      end

      participation.assigned_at  ||= first_at
      participation.completed_at ||= first_at        # 지표가 세는 기준
      participation.rewarded_at  ||= first_at        # 재평가(Rewarder)가 재지급 못 하게 선점
      participation.reward_points_awarded = 0        # 레거시는 보너스 미지급
      participation.save!
      created += 1
    end

    # 레거시 미션 정리: 참여 report 는 있으나 목표(mission_goals)가 없는 미션 → archived, 보상 0.
    archived = Mission.where(id: Report.where.not(mission_id: nil).select(:mission_id))
                      .where.missing(:mission_goals)
                      .update_all(status: Mission.statuses[:archived], reward_points: 0)

    # created_by_id 백필(가능 범위): 담임(classroom.teacher_id).
    filled = 0
    Mission.where(created_by_id: nil).includes(:classroom).find_each do |mission|
      teacher_id = mission.classroom&.teacher_id
      next if teacher_id.nil?

      mission.update_columns(created_by_id: teacher_id)
      filled += 1
    end

    puts "[missions:backfill_legacy] participation created=#{created} skipped=#{skipped} " \
         "missions_archived=#{archived} created_by_filled=#{filled}"
  end

  desc "백필 검증: 학생별 old(reports distinct mission_id) vs new(완료 participation) 대조(mismatch 출력)"
  task verify_backfill: :environment do
    mismatches = 0
    checked = 0

    User.student.find_each do |user|
      old_count = user.reports.where.not(mission_id: nil).distinct.count(:mission_id)
      new_count = user.mission_participations.where.not(completed_at: nil).count
      checked += 1
      next if old_count == new_count

      mismatches += 1
      puts "MISMATCH user=#{user.id} old=#{old_count} new=#{new_count}"
    end

    if mismatches.zero?
      puts "[missions:verify_backfill] OK — checked=#{checked} mismatch=0 (reader 전환 PR2 게이트 통과)"
    else
      puts "[missions:verify_backfill] FAIL — checked=#{checked} mismatch=#{mismatches} (PR2 전환 금지)"
      abort("verify_backfill mismatch=#{mismatches}")
    end
  end
end
