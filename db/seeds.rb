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

# Gamification catalog (반려 몬스터 도감 + 뱃지 + 케어/진화 상점).
Rake::Task["monsters:seed"].invoke
Rake::Task["badges:seed"].invoke
Rake::Task["shop_items:seed"].invoke

# Book catalog (권장도서 + 고전).
Rake::Task["books:seed"].invoke

# Sample published quiz so 독서게임(quiz/golden/bingo) is playable in development (P5.6).
Rake::Task["quizzes:seed"].invoke

# System settings (P7.4) — default feature flags. Idempotent; never stores API keys.
AppSetting.find_or_create_by!(key: "feature_flags") do |setting|
  setting.value = { "seasonal_banner_enabled" => false }
  setting.description = "전역 기능 플래그(JSON 객체)"
end
puts "Ensured default app_settings feature_flags"
