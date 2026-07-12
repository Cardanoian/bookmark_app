# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Schools (reduced development set — one per 시도교육청).
Rake::Task["schools:seed"].invoke

# Superadmin (총괄관리자) — seeded, never self-registered. school_id is NULL.
superadmin = User.find_or_initialize_by(name: "총괄관리자", school_id: nil, classroom_id: nil)
if superadmin.new_record?
  superadmin.role = :superadmin
  superadmin.password = "changeme1234"
  superadmin.save!
  puts "Created superadmin: #{superadmin.name}"
else
  puts "Superadmin already exists: #{superadmin.name}"
end

# System-owned user (온디맨드 캐시 소유자) — origin=system Quiz 의 created_by(Phase 1 §1.1).
# superadmin 과 같은 신원 규약(name + school_id:nil + classroom_id:nil)으로 멱등 생성한다.
# 학생 트리거 콘텐츠도 이 계정 소유의 system 퀴즈로 저장된다(로그인 불가한 시스템 액터).
system_user = User.find_or_initialize_by(name: "시스템", school_id: nil, classroom_id: nil)
if system_user.new_record?
  system_user.role = :superadmin
  system_user.password = SecureRandom.alphanumeric(24)
  system_user.save!
  puts "Created system user: #{system_user.name}"
else
  puts "System user already exists: #{system_user.name}"
end

# Gamification catalog (반려 몬스터 도감 + 뱃지 + 케어/진화 상점).
Rake::Task["monsters:seed"].invoke
Rake::Task["badges:seed"].invoke
Rake::Task["shop_items:seed"].invoke

# Book catalog (권장도서 + 고전).
Rake::Task["books:seed"].invoke

# Sample published quiz so 독서게임(quiz) is playable in development (P5.6).
Rake::Task["quizzes:seed"].invoke

# System settings (P7.4) — default feature flags. Idempotent; never stores API keys.
# on_demand_games(Phase 2b C3): 온디맨드 게임 콘텐츠 워밍의 전역 kill switch. true=확대(전체 on),
#   false=하드 kill(스코프 무시·전부 오프라인), 미설정=파일럿(스코프 on 만). 학급/학교 스코프
#   오버라이드는 "on_demand_games:classroom:<id>"/":school:<id>" 키로 둔다(app_setting.rb 참조).
AppSetting.find_or_create_by!(key: "feature_flags") do |setting|
  setting.value = { "seasonal_banner_enabled" => false, "on_demand_games" => true }
  setting.description = "전역 기능 플래그(JSON 객체)"
end
puts "Ensured default app_settings feature_flags"
