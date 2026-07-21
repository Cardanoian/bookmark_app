# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require "yaml"

load_seed_data = lambda do |filename|
  path = Rails.root.join("db/seeds", filename)
  data = YAML.safe_load_file(path, aliases: false)
  raise "Seed data must be a mapping: #{path}" unless data.is_a?(Hash)

  data
rescue Psych::Exception => error
  raise "Invalid seed data in #{path}: #{error.message}"
end

accounts_data = load_seed_data.call("accounts.yml")
app_settings_data = load_seed_data.call("app_settings.yml")

# Schools. 검증된 전국 CSV가 있으면 모든 환경에서 전량을 오프라인 적재하고, 파일이 없는
# 개발/테스트 체크아웃에서만 17개 축소 세트로 폴백한다.
schools_csv = Rails.root.join("db/seeds/schools.csv")
Rake::Task[File.exist?(schools_csv) ? "schools:seed_full" : "schools:seed"].invoke

# Superadmin (총괄관리자) — seeded, never self-registered. school_id is NULL.
# 신원·비밀번호는 credentials(:superadmin)를 단일 진실로 읽어 매 시드마다 동기화한다.
# credentials 미설정 시 accounts.yml 의 개발용 기본값을 사용한다.
superadmin_defaults = accounts_data.fetch("superadmin")
superadmin_creds = Rails.application.credentials.superadmin || {}
superadmin_name = superadmin_creds[:name].presence || superadmin_defaults.fetch("name")
superadmin = User.find_or_initialize_by(name: superadmin_name, school_id: nil, classroom_id: nil)
superadmin_new = superadmin.new_record?
superadmin.role = superadmin_defaults.fetch("role")
superadmin.email = superadmin_creds[:email].presence || superadmin_defaults.fetch("email")
superadmin.password = superadmin_creds[:password].presence || superadmin_defaults.fetch("password")
superadmin.save!
puts superadmin_new ? "Created superadmin: #{superadmin.name}" : "Synced superadmin from credentials: #{superadmin.name}"

# System-owned user (온디맨드 캐시 소유자) — origin=system Quiz 의 created_by(Phase 1 §1.1).
# 로그인할 수 없는 시스템 액터이므로 비밀번호는 문서에 저장하지 않고 생성 시 무작위로 부여한다.
system_user_data = accounts_data.fetch("system_user")
system_user = User.find_or_initialize_by(
  name: system_user_data.fetch("name"),
  school_id: nil,
  classroom_id: nil
)
if system_user.new_record?
  system_user.role = system_user_data.fetch("role")
  system_user.password = SecureRandom.alphanumeric(24)
  system_user.save!
  puts "Created system user: #{system_user.name}"
else
  puts "System user already exists: #{system_user.name}"
end

# 역할별 개발 샘플 계정. accounts.yml 의 environment 제외 규칙, 학교, 학급, 사용자 관계를 읽는다.
sample_data = accounts_data.fetch("sample_accounts")
unless sample_data.fetch("excluded_environments", []).include?(Rails.env)
  sample_school_data = sample_data.fetch("school")
  sample_school = School.find_by(neis_code: sample_school_data.fetch("neis_code"))

  if sample_school.nil?
    puts "Sample school unavailable in this environment — skipping role sample accounts."
  else
    seed_user = lambda do |user_data, classroom_id:|
      name = user_data.fetch("name")
      role = user_data.fetch("role")
      email = user_data["email"].presence

      # 전국 시드 도입 전 같은 이름의 합성 학교에 만들어진 샘플을 찾아 실학교로 옮긴다.
      # 교직원은 이메일이 안정 식별자다. 이메일이 없는 학생은 비활성 동명 학교 + 같은 학년/반이
      # 정확히 한 건일 때만 레거시 샘플로 간주해, 실제 동명이인 학생을 잘못 이동하지 않는다.
      user = User.find_by(email: email) if email
      if user.nil?
        legacy_scope = User.joins(:school).where(
          name: name,
          role: role,
          schools: { name: sample_school.name, active: false }
        )
        if classroom_id
          target_classroom = Classroom.find(classroom_id)
          legacy_scope = legacy_scope.joins(:classroom).where(
            classrooms: { grade: target_classroom.grade, class_no: target_classroom.class_no }
          )
        else
          legacy_scope = legacy_scope.where(classroom_id: nil)
        end
        legacy_candidates = legacy_scope.limit(2).to_a
        user = legacy_candidates.first if legacy_candidates.one?
      end
      user ||= User.find_or_initialize_by(name: name, school_id: sample_school.id, classroom_id: classroom_id)

      if user.new_record?
        user.role = role
        user.password = user_data.fetch("password")
        user.email = email
        user.save!
        puts "Created sample #{role}: #{name} @ #{sample_school.name}"
      else
        identity_changed = user.school_id != sample_school.id || user.classroom_id != classroom_id
        user.school = sample_school if identity_changed
        user.classroom_id = classroom_id if identity_changed
        user.email = email if email && user.email.blank?

        if identity_changed || user.changed?
          user.save!
          puts "Synced sample #{role}: #{name} @ #{sample_school.name}"
        else
          puts "Sample #{role} already exists: #{name}"
        end
      end

      user
    end

    users_by_key = {}
    classrooms_by_key = {}
    sample_users = sample_data.fetch("users")

    # 담임처럼 학급에 속하지 않은 계정을 먼저 만들어 학급의 teacher 참조를 해석한다.
    sample_users.reject { |user_data| user_data["classroom"] }.each do |user_data|
      users_by_key[user_data.fetch("id")] = seed_user.call(user_data, classroom_id: nil)
    end

    sample_data.fetch("classrooms").each do |classroom_data|
      teacher_key = classroom_data.fetch("teacher")
      teacher = users_by_key.fetch(teacher_key) do
        raise "Unknown sample teacher '#{teacher_key}' in accounts.yml"
      end
      classroom = Classroom.find_or_initialize_by(
        school_id: sample_school.id,
        # 샘플 학급은 현재 학년도로 생성해 로그인 폼 기본 학년도(현재)에서 바로 조회된다.
        # accounts.yml 에 academic_year 를 명시하면 그 값이 우선한다(과거 학년도 샘플 고정 등).
        academic_year: classroom_data["academic_year"] || Classroom.current_academic_year,
        grade: classroom_data.fetch("grade"),
        class_no: classroom_data.fetch("class_no")
      )
      classroom.teacher ||= teacher
      classroom.save!
      classrooms_by_key[classroom_data.fetch("id")] = classroom
    end

    sample_users.select { |user_data| user_data["classroom"] }.each do |user_data|
      classroom_key = user_data.fetch("classroom")
      classroom = classrooms_by_key.fetch(classroom_key) do
        raise "Unknown sample classroom '#{classroom_key}' in accounts.yml"
      end
      users_by_key[user_data.fetch("id")] = seed_user.call(user_data, classroom_id: classroom.id)
    end
  end
end

# Gamification catalog (반려 몬스터 도감 + 뱃지). 상점은 menu_refactor 심화 PR7 에서 제거됨.
Rake::Task["monsters:seed"].invoke
Rake::Task["badges:seed"].invoke

# Book catalog. ISBN이 검증된 전량 TSV만 정본으로 적재한다. 파일이 없으면 seed_full이
# 안내 후 no-op 하며, ISBN 없는 제목-only 축소 카탈로그로 폴백하지 않는다.
Rake::Task["books:seed_full"].invoke

# 최초 설치의 공식 추천도서. 이후에는 총괄관리자가 /admin/recommendation_imports 에서 올린
# 최신 파일이 단일 진실이므로, 업로드 이력이 전혀 없는 DB 에서만 번들 XLSX 를 초기 적재한다.
if RecommendationImport.none?
  recommendation_xlsx = Dir[Rails.root.join("docs", "*.xlsx")].find do |path|
    File.basename(path).unicode_normalize(:nfc).include?("추천도서목록")
  end
  if recommendation_xlsx
    result = Recommendations::Importer.new(
      path: recommendation_xlsx,
      filename: File.basename(recommendation_xlsx)
    ).call(imported_by: superadmin)
    puts "Seeded official recommendations: #{result.recommendation_import.item_count} books"
  else
    puts "Official recommendation XLSX unavailable — skipping initial recommendation import."
  end
end

# 저장된 Gemini 생성 줄거리(db/seeds/book_summaries.yml)를 도서 적재(seed_full + 추천 XLSX) 뒤
# 주입한다. summary 가 blank 인 책만 채우며, 무키·YAML 없음에도 크래시 0(멱등·무네트워크). 이로써
# 무키 배포도 시드만으로 접지 요약을 확보한다(AI 퀴즈 워밍 폴백·게임 가용성 게이트의 summary 소스).
Rake::Task["books:seed_summaries"].invoke

# 큐레이션 게임 문항(db/seeds/book_quizzes.yml)을 도서·요약 적재 뒤 CuratedQuiz 로 물질화한다(Stage 2).
# 큐레이션 있는 책은 학생에게 그 검수 문항이 출제되고 제네릭 오프라인/미검증 AI로 덮이지 않는다.
Rake::Task["books:seed_quizzes"].invoke

# Sample published quiz so 독서게임(quiz) is playable in development (P5.6).
Rake::Task["quizzes:seed"].invoke

# System settings (P7.4). YAML 문서의 기본값은 최초 생성 때만 적용해 관리자 변경을 보존한다.
app_settings_data.fetch("app_settings").each do |setting_data|
  setting = AppSetting.find_or_create_by!(key: setting_data.fetch("key")) do |new_setting|
    new_setting.value = setting_data.fetch("value")
    new_setting.description = setting_data["description"]
  end
  puts "Ensured default app_setting: #{setting.key}"
end
