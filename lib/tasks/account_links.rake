# 계정 연동(MERGE) 운영·관측 rake(account_linking_seasons_plan §Phase 5). 시드가 아니라 운영 태스크다.
#   account_links:audit             — 병합·되돌리기 감사 요약 + FK 무결성(읽기 전용, snapshot PII 미출력).
#   account_links:purge_credentials — 되돌리기 창 경과·미되돌림 병합의 snapshot digest nullify(멱등).
namespace :account_links do
  desc "계정 연동 병합·되돌리기 감사 요약 + FK 무결성 리포트(읽기 전용, snapshot PII 미출력)"
  task audit: :environment do
    total = AccountMerge.count
    reversed = AccountMerge.where.not(reversed_at: nil).count
    active = total - reversed

    puts "== 계정 연동 감사 (#{Time.current.strftime('%Y-%m-%d %H:%M')}) =="
    puts "총 병합: #{total} · 활성: #{active} · 되돌림: #{reversed}"

    recent = AccountMerge.includes(:surviving_user, :performed_by).order(created_at: :desc).limit(20).to_a
    if recent.any?
      puts "\n[최근 병합 #{recent.size}건]"
      recent.each do |merge|
        counts = merge.moved_counts || {}
        summary = %w[reports monsters].map { |key| "#{key}=#{counts[key] || 0}" }.join(" ")
        status = merge.reversed_at ? "되돌림(#{merge.reversed_at.strftime('%Y-%m-%d')})" : "활성"
        performer = merge.performed_by&.name || "학생 본인"
        survivor = merge.surviving_user&.name || "(삭제)"
        # snapshot(PII) 은 절대 출력하지 않는다 — 요약 필드만.
        puts "  ##{merge.id} 생존자=#{survivor} #{summary} 수행=#{performer} " \
             "#{merge.created_at.strftime('%Y-%m-%d %H:%M')} [#{status}]"
      end
    else
      puts "\n병합 기록이 없습니다."
    end

    puts "\n[FK 무결성]"
    if ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)
      violations = ActiveRecord::Base.connection.select_all("PRAGMA foreign_key_check").to_a
      if violations.empty?
        puts "  위반 없음 ✓"
      else
        puts "  ⚠️ FK 위반 #{violations.size}건: #{violations.first(10).inspect}"
      end
    else
      puts "  (SQLite 아님 — foreign_key_check 스킵)"
    end
  end

  desc "되돌리기 창(교사 14일) 경과·미되돌림 병합의 snapshot password_digest purge(멱등, PII 보존기간 제한)"
  task purge_credentials: :environment do
    result = Accounts::PurgeCredentialsJob.new.perform
    window_days = (Accounts::PurgeCredentialsJob::PURGE_WINDOW / 1.day).to_i

    puts "== 자격증명 purge (#{Time.current.strftime('%Y-%m-%d %H:%M')}) =="
    puts "되돌리기 창(#{window_days}일) 경과·미되돌림 대상 스캔: #{result[:scanned]}건, digest purge: #{result[:purged]}건"
    puts "주의: purge 후 총괄 reverse 는 구조를 복원하지만, 복원된 placeholder 는 비밀번호가 없어 로그인 불가"
    puts "      → 담임이 학생관리에서 비밀번호를 재설정해야 합니다."
  end
end
