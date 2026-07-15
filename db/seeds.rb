# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Schools (reduced development set — one per 시도교육청).
Rake::Task["schools:seed"].invoke

# Superadmin (총괄관리자) — seeded, never self-registered. school_id is NULL.
# 신원·비밀번호는 credentials(:superadmin)를 단일 진실로 읽어 매 시드마다 동기화한다(리포에
# 하드코딩 금지). credentials 미설정 시 폴백값 사용. 이름 변경 시 이전 이름 계정은 별도로 남는다.
superadmin_creds = Rails.application.credentials.superadmin || {}
superadmin_name = superadmin_creds[:name].presence || "총괄관리자"
superadmin = User.find_or_initialize_by(name: superadmin_name, school_id: nil, classroom_id: nil)
superadmin_new = superadmin.new_record?
superadmin.role = :superadmin
# 총괄관리자도 교직원 이메일 로그인(sessions#staff_create) 대상이므로 이메일을 부여한다.
# credentials(:superadmin → :email) 단일 진실, 미설정 시 폴백. 매 시드마다 동기화한다.
superadmin.email = superadmin_creds[:email].presence || "admin@example.com"
superadmin.password = superadmin_creds[:password].presence || "changeme1234"
superadmin.save!
puts superadmin_new ? "Created superadmin: #{superadmin.name}" : "Synced superadmin from credentials: #{superadmin.name}"

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

# 역할별 개발 샘플 계정 (학생·담임교사·교무관리자·사서) — 모두 같은 학교 소속으로 하드코딩.
# 교직원(교사·교무관리자·사서)은 이메일로, 학생은 (학교·학급·이름) 튜플로 로그인한다(sessions_controller).
# superadmin 은 위에서 credentials(:superadmin) 로 별도 시드된다. 모든 계정은 멱등(신원 튜플).
sample_school = School.find_by(neis_code: "7150001") # 포항원동초등학교 (schools:seed 로 선적재)

if sample_school.nil?
  puts "Sample school (neis_code 7150001) not found — skipping role sample accounts."
else
  # 신원 튜플로 멱등 생성하는 헬퍼. email 등 부가 속성은 attrs 로 전달.
  # 기존 계정이면 비어 있는 attrs(예: email 컬럼 신설 후)만 백필한다 — 비번은 건드리지 않아
  # db:reset 없이 재시드만으로 교직원 이메일 로그인이 가능해진다.
  seed_user = lambda do |name:, role:, classroom_id:, password:, **attrs|
    user = User.find_or_initialize_by(name: name, school_id: sample_school.id, classroom_id: classroom_id)
    if user.new_record?
      user.role = role
      user.password = password
      attrs.each { |attr, value| user.public_send("#{attr}=", value) }
      user.save!
      puts "Created sample #{role}: #{name} @ #{sample_school.name}"
    else
      backfill = attrs.reject { |attr, _| user.public_send(attr).present? }
      if backfill.any?
        backfill.each { |attr, value| user.public_send("#{attr}=", value) }
        user.save!
        puts "Backfilled #{backfill.keys.join(', ')} on sample #{role}: #{name}"
      else
        puts "Sample #{role} already exists: #{name}"
      end
    end
    user
  end

  # 담임교사 — 학급의 담임이 되므로 학생·학급보다 먼저 만든다.
  # 교직원(교사·교무관리자·사서)은 이메일로 로그인한다(sessions#staff_create).
  sample_teacher = seed_user.call(name: "김담임", role: :teacher, classroom_id: nil,
    password: "teacher1234", email: "teacher@example.com")

  # 담임 학급(3학년 1반) — 학생이 소속될 학급. 위 교사를 담임으로 연결.
  sample_classroom = Classroom.find_or_create_by!(school_id: sample_school.id, grade: 3, class_no: 1) do |classroom|
    classroom.teacher = sample_teacher
  end

  # 학생 — 위 학급 소속. 학생은 튜플(학교·학급·이름)로 로그인하므로 이메일이 없다.
  seed_user.call(name: "이학생", role: :student, classroom_id: sample_classroom.id, password: "student1234")

  # 교무관리자·사서 — 학교 소속(학급 없음). 이메일로 로그인한다.
  seed_user.call(name: "박교무", role: :school_admin, classroom_id: nil,
    password: "schooladmin1234", email: "schooladmin@example.com")
  seed_user.call(name: "최사서", role: :librarian, classroom_id: nil,
    password: "librarian1234", email: "librarian@example.com")
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
