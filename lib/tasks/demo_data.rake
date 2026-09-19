# 공개 체험 학급의 운영 데이터 점검·일회성 재적재.
# 스케줄러에는 연결하지 않는다. 적용은 DEMO_DEPLOYMENT와 정확한 확인 문자열이 모두 필요하다.
namespace :demo_data do
  desc "Audit the public demo classroom without changing data"
  task public_classroom_audit: :environment do
    result = DemoData::PublicClassroomRefresh.new(backup_database: false).preview
    puts "[demo-refresh] DRY RUN"
    result.each { |key, value| puts "  #{key}=#{value}" }
  end

  desc "Back up and rebuild the public demo classroom once from reviewed seed data"
  task public_classroom_refresh: :environment do
    service = DemoData::PublicClassroomRefresh.new(confirmation: ENV["CONFIRM"])
    result = service.call!
    puts "[demo-refresh] backup_sha256=#{result.dig(:backup, :sha256)}"
  end

  desc "Audit demo classrooms whose seed defines debate topics without changing data"
  task discussion_audit: :environment do
    puts "[discussion-rebuild] DRY RUN"
    DemoData::DiscussionRebuild.new.preview.each { |row| puts "  #{row.inspect}" }
  end

  desc "Back up and rebuild only the discussions of demo classrooms whose seed defines debate topics"
  task discussion_rebuild: :environment do
    result = DemoData::DiscussionRebuild.new(confirmation: ENV["CONFIRM"]).call!
    puts "[discussion-rebuild] backup_sha256=#{result.dig(:backup, :sha256)}"
  end
end
