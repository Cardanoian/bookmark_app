# frozen_string_literal: true

require "yaml"
require "zlib"

# 데모(가상 사용) 데이터 시더 — "이 앱을 많이 사용한 것처럼" 보이는 학급·학생·활동을 만든다.
#
# db/seeds/demo/*.yml (학급별 1파일, Sonnet 에이전트 생성)을 읽어 학생·독후감·게임·몬스터·
# 커뮤니티·미션·시즌점수·뱃지를 **멱등**하게 생성한다. seeds.rb 가 SEED_DEMO=1 + 비production
# 게이트에서만 호출한다(운영에 가짜 아동 데이터 유입 차단).
#
# 멱등성: 학급에 이미 독후감이 있으면 활동 생성은 건너뛰되, 학생 프로필(닉네임·랭킹 공개·동의)은
# 최신 스키마로 동기화한다. 재실행(SEED_DEMO=1 bin/rails db:seed)은 활동을 중복 생성하지 않는다.
#
# 도메인 일관성: 포인트=경험치=Σ(독후감 등급점수 + 게임/퀴즈 + 미션보상)로 산정하고 같은 값을
# 현재 학년도 season_scores 에 적재한다. 뱃지는 활동을 모두 만든 뒤 refresh_badges! 로 실제
# ReadingStats 에서 부여해 "활동과 어긋나지 않는" 상태를 만든다. 몬스터는 라인 단위로 직접 지급하고
# 진화분은 evolved_at 을 세팅한다(스타터/마일스톤 서비스 우회 — 데모는 결과 상태만 필요).
class DemoSeeder
  STUDENT_PASSWORD = "student1234"
  TEACHER_PASSWORD = "teacher1234"

  # 활성 게임 종류(게임 재구성 이후 신규 기록 가능한 4종). 모두 책 연결 플레이.
  GAME_TYPES = %i[quiz whoami book sequel].freeze

  POINTS_PER_GAME_PLAY = 10
  POINTS_PER_QUIZ_ATTEMPT = 10

  # 글을 써야 끝나는 게임(책 소개 대결·뒷이야기 이어쓰기). 이 두 게임의 완료 기록은 같은 책의 글과 함께 만든다
  # — 화면은 쓴 글이 있어야 "완료"로 보이므로(StudentLibraryQuery::WRITTEN_GAMES), 글 없는 기록은 볼 글이 없는
  # "완료"가 됐다(운영 체험 이도현 『검피 아저씨의 뱃놀이』, 2026-09-19).
  WRITTEN_GAME_TYPES = %i[book sequel].freeze
  # 책별 예시 글 풀(ISBN-13 → { title, book_intro, book_sequel, forum_posts }).
  SOCIAL_TEXTS_PATH = Rails.root.join("db/seeds/book_social.yml")
  # 시드가 만든 뒷이야기는 담임이 이미 승인한 글로 둔다(교사 '뒷이야기 검토' 대기 수는 정본 글만).
  GAME_SEQUEL_COMMENT = "상상력이 돋보이는 이야기예요! 인물의 마음을 잘 이어 썼어요."
  # 글 쓰는 게임의 날짜: 1학기(5월 1일~7월 20일)에 주로, 2학기 9월에 조금, 8월(여름방학)은 비운다.
  WRITING_TERM_START = [ 5, 1 ].freeze
  WRITING_TERM_END = [ 7, 20 ].freeze
  WRITING_SEPTEMBER_SHARE = 0.15

  # 초등학생 데모 계정용 독서 별칭. 접두어와 독서 관련 낱말을 조합해 실명·숫자 없이 고유한
  # 닉네임을 만든다(29 × 26 = 754개 — 현재 데모 학생 745명보다 많음).
  NICKNAME_PREFIXES = %w[
    반짝 포근 신나는 즐거운 용감한 다정한 씩씩한 재잘 꿈꾸는 상상 호기심 따뜻한
    싱그런 쌩쌩 알록달록 꼬마 행복한 초롱 달빛 별빛 햇살 구름 바람 무지개 쑥쑥
    반가운 톡톡 빙글 노랑
  ].freeze
  NICKNAME_SUFFIXES = %w[
    책벌레 책콩 독서왕 이야기씨 동화요정 책탐험대 책나무 책구름 책바다 책별 책달
    책여행자 글자친구 문장요정 단어요정 이야기별 동화별 그림책친구 책갈피 책보물
    이야기보물 책모험가 독서새싹 책새싹 책빛 책마법사
  ].freeze

  def initialize(root: Rails.root.join("db/seeds/demo"), io: $stdout, only_files: nil)
    @root = root
    @io = io
    @only_files = Array(only_files).presence&.map { |filename| validate_seed_filename!(filename) }
    @totals = Hash.new(0)
  end

  def call
    ensure_schools!

    files = (Dir[File.join(@root, "*.yml")] - [ schools_file_path ]).sort
    files.select! { |path| @only_files.include?(File.basename(path)) } if @only_files
    validate_requested_files!(files)
    if files.empty?
      @io.puts "  [demo] db/seeds/demo/*.yml 없음 — 데모 시드 건너뜀."
      return
    end

    data_sources = files.map do |path|
      [ path, load_seed_data(path) ]
    rescue => e
      @io.puts "  [demo] #{File.basename(path)} 실패: #{e.class} #{e.message}"
      raise
    end

    assign_student_profiles!(data_sources)
    validate_unique_student_names!(data_sources)
    validate_unique_student_nicknames!(data_sources)

    data_sources.each do |path, data|
      seed_classroom(data, File.basename(path))
    rescue => e
      @io.puts "  [demo] #{File.basename(path)} 실패: #{e.class} #{e.message}"
      raise
    end

    @io.puts "  [demo] 완료: " + @totals.map { |k, v| "#{k}=#{v}" }.join(" ")
  end

  # 일회성 운영 정비가 전체 데모 학교를 건드리지 않고 특정 학급의 정본만 읽고 재적재할 때 쓰는
  # 제한된 공개 API. 파일명은 디렉터리 이동이 없는 basename만 허용한다.
  def seed_data_for(filename)
    filename = validate_seed_filename!(filename)
    path = File.join(@root, filename)
    raise ArgumentError, "데모 시드 파일 없음: #{filename}" unless File.file?(path)

    load_seed_data(path)
  end

  # 이미 적재된 데모 학급의 토론방·글·좋아요만 정본으로 다시 만드는 제한된 공개 API
  # (DemoData::DiscussionRebuild 전용). 학생·독후감·게임 같은 다른 활동은 건드리지 않는다.
  # 명단 일치 확인·트랜잭션·백업은 호출자가 책임진다.
  def reseed_discussions!(filename, classroom)
    data = seed_data_for(filename)
    users = classroom.users.where(role: :student).index_by(&:name)
    students = data.fetch("students").map { |sd| { sd:, user: users.fetch(sd.fetch("name").to_s) } }
    @rng = Random.new(Zlib.crc32("#{classroom.school.neis_code}-#{classroom.grade}-#{classroom.class_no}"))

    Topic.where(classroom:).find_each(&:destroy!)
    seed_topics_and_forum(Array(data["topics"]), classroom, students, peers: users.values)
  end

  private

  def validate_seed_filename!(filename)
    value = filename.to_s
    return value if value.match?(/\A[a-z0-9_]+\.yml\z/) && value != File.basename(schools_file_path)

    raise ArgumentError, "데모 시드 파일명은 db/seeds/demo 안의 YAML basename이어야 합니다"
  end

  def validate_requested_files!(files)
    return unless @only_files

    missing = @only_files - files.map { |path| File.basename(path) }
    raise ArgumentError, "데모 시드 파일 없음: #{missing.join(', ')}" if missing.any?
  end

  # 데모 학급이 사는 **가상 학교**를 먼저 확보한다(`db/seeds/demo/schools.yml`).
  # 전국 NEIS 스냅샷에 없는 학교라 `schools:seed_full` 이 만들어 주지 않으므로 여기서 만든다.
  # `data_source: manual` 이라 전국 스냅샷을 다시 적재해도 비활성화되지 않는다.
  # 이미 있으면 이름·지역만 규약값으로 맞추고 활성 상태를 되살린다(멱등).
  def ensure_schools!
    return unless File.exist?(schools_file_path)

    entries = Array(YAML.safe_load_file(schools_file_path, aliases: false)&.fetch("schools", nil))
    return if entries.empty?

    created = entries.count do |entry|
      school = School.find_or_initialize_by(neis_code: entry.fetch("neis_code").to_s)
      new_record = school.new_record?
      school.assign_attributes(
        name: entry.fetch("name"),
        region: entry["region"].presence,
        gu: entry["gu"].presence,
        office_code: entry["office_code"].presence,
        address: entry["address"].presence,
        active: true,
        data_source: "manual"
      )
      school.save!
      new_record
    end

    @io.puts "  [demo] 가상 학교 #{entries.size}곳 확인(신규 #{created}곳)."
  end

  def schools_file_path
    File.join(@root, "schools.yml")
  end

  # 신규 데모 학급은 검증된 기존 활동 구성을 템플릿으로 재사용할 수 있다. 템플릿 파일은
  # 학생의 활동량·콘텐츠를 제공하고, 참조 파일은 학교·담임·학생 명단만 선언한다.
  # student_names 는 템플릿의 20명보다 적거나 많아도 된다(현재 18~22명 지원). 인원이
  # 많을 때는 활동 프로필을 순환 재사용하되 학생 이름은 항상 별개로 검증한다. activity_level
  # (high/balanced/low)은 학생 활동과 미션 완료율을 함께 조절해 학급별 사용량 차이를 만든다.
  #
  # student_names 항목은 문자열(이름만) 또는 해시를 쓸 수 있다. 해시는 name 외에
  # nickname(랭킹 별칭 고정 — 전역 닉네임 카운터를 소비하지 않아 기존 학급 닉네임이 밀리지 않는다),
  # activity_level(그 학생만의 활동량), 그 밖의 학생 키(reports·game_plays 등 직접 지정)를 받는다.
  def load_seed_data(path)
    data = YAML.safe_load_file(path, aliases: false)
    return data unless data["template"].present?

    template_name = data.fetch("template").to_s
    unless template_name.match?(/\A[a-z0-9_]+\.yml\z/)
      raise ArgumentError, "template은 db/seeds/demo 안의 YAML 파일명이어야 합니다"
    end

    template = YAML.safe_load_file(@root.join(template_name), aliases: false)
    entries = Array(data.fetch("student_names"))
    names = entries.map { |entry| entry.is_a?(Hash) ? entry.fetch("name").to_s : entry.to_s }
    overrides = entries.map { |entry| entry.is_a?(Hash) ? entry.except("name") : {} }
    source_students = template.fetch("students")
    activity_level = data["activity_level"].presence || "high"

    unless names.size.between?(18, 22)
      raise ArgumentError, "student_names는 18명에서 22명 사이여야 합니다"
    end
    if names.any?(&:blank?) || names.uniq.size != names.size
      raise ArgumentError, "student_names에는 비어 있거나 중복된 이름을 넣을 수 없습니다"
    end

    seed_data = template.merge(data.except("template", "student_names", "activity_level"))
    profiles = source_students.cycle.take(names.size)
    debate_posts = balanced_debate_posts(profiles, activity_scale_for(activity_level))
    seed_data.merge(
      "missions" => scale_missions(Array(seed_data["missions"]), activity_scale_for(activity_level)),
      "students" => profiles.zip(names, overrides).each_with_index.map do |(student, name, override), index|
        level = override["activity_level"].presence || activity_level
        scaled = scale_student_activity(student, activity_scale_for(level))
        scaled = scaled.merge("forum_posts" => debate_posts[index]) if debate_posts
        scaled.merge("name" => name).merge(override.except("activity_level"))
      end
    )
  end

  # 찬반 토론 글(구조화 + stance)은 학생별로 앞에서 자르지 않고 학급 단위로 논제마다 고른다.
  # 학생별로 자르면 글이 한 편뿐인 학생(반대 글이 여기 많다)이 통째로 빠져, 활동량이 낮은 학급의
  # 논제가 찬성만 남거나 비었다. 논제마다 활동량만큼(최소 2편) 남기되 소수 입장을 비율대로(최소 1편)
  # 함께 남긴다. 명단이 템플릿보다 길어 프로필을 다시 쓰면 같은 글은 한 학급에 한 번만 쓴다.
  # 활동량이 high(1.0)면 템플릿 글을 그대로 둔다. 찬반 글이 없는 템플릿은 nil(학생별 규칙 유지).
  def balanced_debate_posts(profiles, scale)
    seen = Set.new
    entries = profiles.each_with_index.flat_map do |profile, index|
      Array(profile["forum_posts"]).filter_map do |post|
        next unless post.is_a?(Hash) && post["stance"].present?

        [ index, post ] if seen.add?(post.fetch("text"))
      end
    end
    return if entries.empty?

    kept = entries.group_by { |_index, post| post.fetch("topic") }
                  .flat_map { |_topic, rows| sample_debate_rows(rows, scale) }
    profiles.each_index.map { |index| kept.filter_map { |owner, post| post if owner == index } }
  end

  def sample_debate_rows(rows, scale)
    keep = [ (rows.size * scale).round, [ 2, rows.size ].min ].max
    return rows if keep >= rows.size

    minority, majority = rows.partition { |_index, post| post.fetch("stance") == "con" }
                             .sort_by(&:size)
    minority_keep = minority.empty? ? 0 : ((minority.size * keep.fdiv(rows.size)).round).clamp(1, minority.size)
    chosen = minority.first(minority_keep) + majority.first(keep - minority_keep)
    rows.select { |row| chosen.include?(row) }
  end

  def activity_scale_for(level)
    { "high" => 1.0, "balanced" => 0.7, "low" => 0.4 }.fetch(level.to_s)
  rescue KeyError
    raise ArgumentError, "activity_level은 high, balanced, low 중 하나여야 합니다"
  end

  def scale_missions(missions, scale)
    return missions if scale == 1.0

    missions.map do |mission|
      mission.merge("completion_rate" => (mission.fetch("completion_rate", 0.5).to_f * scale).round(2))
    end
  end

  def scale_student_activity(student, scale)
    return student if scale == 1.0

    reports = Array(student["reports"])
    report_count = (reports.size * scale).floor
    scaled = student.merge(
      "reports" => reports.first(report_count),
      "game_plays" => (student.fetch("game_plays", 0).to_i * scale).floor,
      "quiz_attempts" => (student.fetch("quiz_attempts", 0).to_i * scale).floor,
      "monster_lines" => (student.fetch("monster_lines", 0).to_i * scale).floor,
      "evolved" => (student.fetch("evolved", 0).to_i * scale).floor,
      "forum_posts" => Array(student["forum_posts"]).first((Array(student["forum_posts"]).size * scale).floor)
    )

    # 읽은 책이 전혀 없는 학생은 책 소개·뒷이야기 활동도 만들지 않는다.
    scaled.except!("book_intro", "book_sequel") if report_count.zero?
    scaled
  end

  # 랭킹 프로필은 실명과 분리된 데모 전용 독서 별칭으로 일괄 생성한다. 파일명 순서 + 학생
  # 순서로 조합을 골라 모든 데모 학급을 통틀어 안정적으로 고유하며, 실제 학생 이름을 노출하지
  # 않는다. 인원이 홀수인 학급은 절반 미만(내림)만 랭킹 공개에 참여시킨다.
  #
  # YAML 에 nickname 을 직접 적은 학생은 **전역 카운터를 소비하지 않는다**. 카운터는 파일명 정렬
  # 순서를 따르는 위치 기반이라, 소비하면 뒤 학급의 닉네임이 통째로 밀려 같은 학교 안에서
  # [school_id, nickname] UNIQUE 에 걸린다. 명시 닉네임은 754개 상한도 쓰지 않는다.
  def assign_student_profiles!(data_sources)
    nickname_sequence = 0

    data_sources.each do |_path, data|
      students = data.fetch("students")
      ranking_participant_count = students.size / 2

      students.each_with_index do |student, index|
        if student["nickname"].blank?
          nickname_sequence += 1
          student["nickname"] = demo_nickname_for(nickname_sequence)
        end
        student["ranking_opted_in"] = index < ranking_participant_count if student["ranking_opted_in"].nil?
      end
    end
  end

  def demo_nickname_for(sequence)
    index = sequence - 1
    capacity = NICKNAME_PREFIXES.size * NICKNAME_SUFFIXES.size
    if index >= capacity
      raise ArgumentError, "데모 학생 수(#{sequence})가 준비된 닉네임 수(#{capacity})를 초과했습니다"
    end

    "#{NICKNAME_PREFIXES[index / NICKNAME_SUFFIXES.size]}#{NICKNAME_SUFFIXES[index % NICKNAME_SUFFIXES.size]}"
  end

  # 데모 환경에서는 학급을 넘어 학생 이름도 고유하게 유지한다. 로그인·데모 확인 시
  # 같은 이름을 구별해야 하는 혼란을 막기 위한 데이터 자산 규약이다.
  def validate_unique_student_names!(data_sources)
    occurrences = data_sources.flat_map do |path, data|
      data.fetch("students").map { |student| [ student.fetch("name").to_s, File.basename(path) ] }
    end
    duplicates = occurrences.group_by(&:first).select { |_, entries| entries.size > 1 }
    return if duplicates.empty?

    details = duplicates.map { |name, entries| "#{name}(#{entries.map(&:last).join(', ')})" }.join(", ")
    raise ArgumentError, "데모 학생 이름 중복: #{details}"
  end

  def validate_unique_student_nicknames!(data_sources)
    occurrences = data_sources.flat_map do |path, data|
      data.fetch("students").map { |student| [ student.fetch("nickname").to_s, File.basename(path) ] }
    end
    duplicates = occurrences.group_by(&:first).select { |_, entries| entries.size > 1 }
    return if duplicates.empty?

    details = duplicates.map { |nickname, entries| "#{nickname}(#{entries.map(&:last).join(', ')})" }.join(", ")
    raise ArgumentError, "데모 학생 닉네임 중복: #{details}"
  end

  def seed_classroom(data, filename)
    cr = data.fetch("classroom")
    school = School.find_by(neis_code: cr.fetch("school_neis_code").to_s)
    unless school
      @io.puts "  [demo] #{filename}: 학교(neis=#{cr['school_neis_code']}) 없음 — 건너뜀."
      return
    end

    academic_year = (cr["academic_year"] || Classroom.current_academic_year).to_i
    grade = cr.fetch("grade").to_i
    class_no = cr.fetch("class_no").to_i
    label = cr["school_label"] || school.name

    students_data = data.fetch("students")
    classroom = Classroom.find_by(school_id: school.id, academic_year:, grade:, class_no:)
    if classroom&.reports&.exists?
      sync_existing_student_profiles!(students_data, school:, classroom:, teacher_data: data.fetch("teacher"))
      pending = pending_students(students_data, classroom:)
      if pending.empty?
        @io.puts "  [demo] #{filename}: #{label} #{grade}-#{class_no} 활동은 이미 시드됨 — 학생 프로필 동기화."
        return
      end

      top_up_classroom(data, pending, school:, classroom:, label:)
      return
    end

    @rng = Random.new(Zlib.crc32("#{school.neis_code}-#{grade}-#{class_no}"))

    ActiveRecord::Base.transaction do
      teacher = seed_teacher(data.fetch("teacher"), school)
      classroom ||= Classroom.create!(school:, academic_year:, grade:, class_no:, teacher:)
      classroom.update!(teacher:) if classroom.teacher_id.nil?

      students = students_data.map { |sd| seed_student(sd, school, classroom, teacher) }

      seed_missions(Array(data["missions"]), classroom, teacher, students)
      seed_topics_and_forum(Array(data["topics"]), classroom, students)
      seed_board_and_cheers(
        students,
        classroom,
        featured_report_keys: data.dig("story", "featured_report_keys"),
        require_featured_reports: data["story"].present?
      )
      seed_social_games(students, classroom, sequel_definitions: data["book_sequels"])

      students.each { |st| finalize_student(st) }

      @totals[:classrooms] += 1
      @totals[:students] += students.size
      @io.puts "  [demo] #{label} #{grade}-#{class_no}: 학생 #{students.size}명 + 활동 생성"
    end
  end

  def pending_students(students_data, classroom:)
    existing = classroom.users.where(role: :student).pluck(:name).to_set
    students_data.reject { |sd| existing.include?(sd.fetch("name").to_s) }
  end

  # 이미 활동이 있는 학급에 **명단에 없던 학생만** 채운다(샘플 3-1 을 21명으로 확장하는 경로).
  # 기존 학생의 독후감·포인트·경험치·시즌점수·뱃지는 손대지 않고, 새 학생만 활동을 생성한다.
  # 학급 단위 콘텐츠(토론방·미션)는 아직 없을 때만 만들어 재실행에 안전하다. 또래 상호작용
  # (좋아요·응원·투표)의 풀은 기존 학생까지 포함한 학급 전원이라 학급이 자연스럽게 보인다.
  def top_up_classroom(data, pending, school:, classroom:, label:)
    @rng = Random.new(Zlib.crc32("#{school.neis_code}-#{classroom.grade}-#{classroom.class_no}"))

    ActiveRecord::Base.transaction do
      teacher = seed_teacher(data.fetch("teacher"), school)
      classroom.update!(teacher:) if classroom.teacher_id.nil?

      students = pending.map { |sd| seed_student(sd, school, classroom, teacher) }
      peers = classroom.users.where(role: :student).order(:id).to_a

      top_up_missions(Array(data["missions"]), classroom, teacher, students)
      seed_topics_and_forum(Array(data["topics"]), classroom, students, peers:)
      seed_board_and_cheers(
        students,
        classroom,
        peers:,
        featured_report_keys: data.dig("story", "featured_report_keys")
      )
      seed_social_games(students, classroom, peers:, sequel_definitions: data["book_sequels"])

      students.each { |st| finalize_student(st) }

      @totals[:classrooms_topped_up] += 1
      @totals[:students] += students.size
      @io.puts "  [demo] #{label} #{classroom.grade}-#{classroom.class_no}: 기존 활동 보존 + 학생 #{students.size}명 추가"
    end
  end

  # ── 계정 ────────────────────────────────────────────────────────────────
  def seed_teacher(td, school)
    email = td.fetch("email").to_s.downcase
    teacher = User.find_or_initialize_by(email:)
    if teacher.new_record?
      teacher.assign_attributes(
        name: td.fetch("name"), role: :teacher, school:, classroom_id: nil,
        password: TEACHER_PASSWORD
      )
      teacher.save!
      @totals[:teachers] += 1
    end
    teacher
  end

  def seed_student(sd, school, classroom, teacher)
    name = sd.fetch("name").to_s
    user = User.find_or_initialize_by(school_id: school.id, classroom_id: classroom.id, name:)
    if user.new_record?
      user.assign_attributes(role: :student, password: STUDENT_PASSWORD)
    end
    apply_student_profile!(user, sd, teacher)
    user.save! if user.new_record? || user.changed?

    st = { user:, sd:, classroom:, report_points: 0, game_points: 0, mission_points: 0,
           reports: [], reports_by_seed_key: {}, shareable: [] }

    seed_reports(st)
    seed_games(st)
    seed_monsters(st)
    st
  end

  # 이미 활동까지 생성된 학급도 스키마 확장 후에는 학생 설정을 갱신해야 한다. 활동은 건드리지
  # 않고, 시드 명단에 있는 학생만 대상으로 하므로 실제 사용자 계정에는 영향을 주지 않는다.
  def sync_existing_student_profiles!(students_data, school:, classroom:, teacher_data:)
    teacher = seed_teacher(teacher_data, school)
    classroom.update!(teacher:) if classroom.teacher_id.nil?

    synced = students_data.count do |sd|
      user = User.find_by(school_id: school.id, classroom_id: classroom.id, name: sd.fetch("name").to_s)
      next false unless user

      apply_student_profile!(user, sd, teacher)
      user.save! if user.changed?
      true
    end
    @totals[:students_profiles_synced] += synced
  end

  # 닉네임·랭킹 공개는 학생이 앱에서 직접 정하는 값이라, 이미 값이 있는 계정은 시드가 덮어쓰지
  # 않는다(실사용 계정의 선택을 재시드가 되돌리지 않게 하는 안전장치).
  def apply_student_profile!(user, student_data, teacher)
    consent_already_recorded = user.ai_consent? && user.ai_consent_at.present?
    recorder_already_set = user.ai_consent? && user.ai_consent_recorded_by_id.present?

    user.assign_attributes(
      nickname: (user.nickname.presence || student_data.fetch("nickname")),
      ranking_opted_in: (user.new_record? ? student_data.fetch("ranking_opted_in") : user.ranking_opted_in),
      ai_consent: true,
      ai_consent_at: (consent_already_recorded ? user.ai_consent_at : Time.current),
      ai_consent_recorded_by_id: (recorder_already_set ? user.ai_consent_recorded_by_id : teacher.id),
      privacy_consent_at: user.privacy_consent_at || Time.current
    )
  end

  # ── 독후감 ──────────────────────────────────────────────────────────────
  def seed_reports(st)
    user = st[:user]
    classroom = st[:classroom]
    Array(st[:sd]["reports"]).each do |rd|
      quality = (rd["quality"] || "b").to_s.downcase
      rubric = report_rubric(rd, quality)
      scored = RubricScorable.score_rubric(rubric)
      book = match_book(rd["book_title"])
      reviewed = rd.fetch("reviewed", true) ? true : false
      created = backdate(rd["days_ago"] || rand_int(3, 60))
      input_mode = rd["input_mode"].presence&.to_sym || (ocr_pick? ? :ocr : :keyboard)
      improvement = rd["improvement"].to_f
      revision_of = report_revision_for!(rd, st)

      report = Report.new(
        user:, classroom:, book: book, book_title: rd["book_title"],
        body: rd["body"].to_s, input_mode:, ai_status: :done,
        rubric: rubric.merge(report_feedback(rd, quality)), revision_of:,
        avg: scored[:avg], level: scored[:level],
        points_awarded: (reviewed ? scored[:points] : 0),
        reviewed:, reviewed_at: (reviewed ? created + rand_int(1, 48).hours : nil),
        teacher_comment: rd["teacher_comment"].presence,
        improvement: (improvement.positive? ? improvement : nil),
        shared: false
      )
      report.save!
      # 데모 독후감은 모두 학생이 '제출한' 글이다. submitted_at 이 비면 Report.submitted 를 쓰는 곳
      # (교사 검토 큐·대시보드·연속 제출일·최근 활동일·챌린지 순위)에서 미제출 초안으로 빠진다.
      report.update_columns(created_at: created, updated_at: created, submitted_at: created)

      st[:report_points] += report.points_awarded.to_i
      st[:reports] << report
      register_report_seed_key!(rd, report, st)
      st[:shareable] << report if reviewed && %w[A B].include?(report.level)
      @totals[:reports] += 1
    end
  end

  # ── 게임(원장 + 퀴즈 시도) ───────────────────────────────────────────────
  # 퀴즈·나는 누구게?는 완료 기록만 만든다(최근 며칠 — 미션 기간 진행도가 여기에 걸려 있다). 책 소개·
  # 뒷이야기는 예시 글이 있는 책에 그 글을 함께 쓰고(write_game_entry!), 날짜는 writing_date 를 따른다.
  # 예시 글 풀이 없는 환경(테스트의 임의 ISBN 도서 등)에서는 예전처럼 완료 기록만 만든다.
  def seed_games(st)
    user = st[:user]
    plays = (st[:sd]["game_plays"] || 0).to_i
    slots = Array.new(plays) { |i| [ i, GAME_TYPES[i % GAME_TYPES.size] ] }
    # 이 학생이 게임한 책 — 글 쓰는 게임의 책을 여기서 피해 '게임으로 만난 책 수'(몬스터 해금 지표)를 지킨다.
    taken = slots.reject { |_i, gtype| WRITTEN_GAME_TYPES.include?(gtype) }.map { |i, _gtype| pool_book(i + user.id).id }.to_set

    slots.each do |i, gtype|
      book = pool_book(i + user.id)
      played_on = Date.current - (i + 1)
      if WRITTEN_GAME_TYPES.include?(gtype) && (written_book = social_book_for(gtype, st[:classroom], i + user.id, taken))
        book = written_book
        played_on = writing_date(user, i)
        taken << book.id
        write_game_entry!(gtype, user, st[:classroom], book, played_on)
      end
      GamePlay.create!(user:, game_type: gtype, book: book, played_on: played_on.to_s)
      st[:game_points] += POINTS_PER_GAME_PLAY
      @totals[:game_plays] += 1
    end

    attempts = (st[:sd]["quiz_attempts"] || 0).to_i
    return if attempts.zero? || quiz_pool.empty?

    attempts.times do |i|
      quiz = quiz_pool[(i + user.id) % quiz_pool.size]
      played = backdate(rand_int(1, 45))
      QuizAttempt.create!(
        user:, quiz:, answers: {}, score: rand_int(60, 100),
        played_at: played, points_awarded: POINTS_PER_QUIZ_ATTEMPT
      )
      st[:game_points] += POINTS_PER_QUIZ_ATTEMPT
      @totals[:quiz_attempts] += 1
    end
  end

  # ── 몬스터(라인 단위 직접 지급) ──────────────────────────────────────────
  def seed_monsters(st)
    user = st[:user]
    lines = (st[:sd]["monster_lines"] || 0).to_i.clamp(0, MonsterSpecies::DESIGN_LINE_COUNT)
    return if lines.zero?

    evolved = (st[:sd]["evolved"] || 0).to_i.clamp(0, lines)
    preferred = preferred_active_monster!(st[:sd]["active_monster_key"])
    dex_nos = monster_dex_nos(lines, user.id, preferred)
    first = nil
    active = nil

    dex_nos.each_with_index do |dex_no, idx|
      stage =
        if idx < evolved
          # 진화분: 대부분 stage 2, 일부 stage 3(최종형).
          (idx.even? && idx < (evolved / 2 + 1)) ? 3 : 2
        else
          1
        end
      species = if preferred&.dex_no == dex_no
        preferred
      else
        MonsterSpecies.find_by(dex_no:, stage:) || MonsterSpecies.find_by(dex_no:, stage: 1)
      end
      next unless species

      obtained = backdate(rand_int(5, 90))
      um = UserMonster.create!(
        user:, monster_species: species, obtained_at: obtained,
        evolved_at: (stage > 1 ? obtained + rand_int(1, 20).days : nil),
        celebrated_at: obtained, nickname: nil
      )
      first ||= um
      active = um if preferred&.dex_no == dex_no
      @totals[:user_monsters] += 1
    end

    user.update_columns(active_monster_id: (active || first).id) if active || first
  end

  # ── 미션 ────────────────────────────────────────────────────────────────
  def seed_missions(missions, classroom, teacher, students)
    build_missions(missions, classroom, teacher).each do |mission, rate|
      assign_mission(mission, rate, students)
    end
  end

  # 이미 발행 미션이 있는 학급(교사가 직접 만든 미션이 도는 학급)에는 템플릿 미션을 새로 만들지 않고
  # 그 미션에 신규 학생만 배정한다. 학급 미션 수가 부풀지 않고 참여자 수도 학급 전원으로 맞는다.
  #
  # 기존 학생의 participation 은 만들지 않는다 — 배정만 하고 미보상(rewarded_at: nil)으로 두면
  # production 의 Missions::ReevaluateJob(config/recurring.yml, 매시 27분)이 목표 달성을 재평가해
  # 나중에 포인트를 지급하므로, "기존 학생 포인트 불변" 이 깨진다(실측: 이도현 +150점).
  def top_up_missions(mission_defs, classroom, teacher, students)
    existing = classroom.missions.published.where(id: MissionGoal.select(:mission_id))
                        .order(:start_date, :id).to_a
    pairs =
      if existing.any?
        existing.map.with_index { |mission, i| [ mission, (mission_defs.dig(i, "completion_rate") || 0.5).to_f ] }
      else
        build_missions(mission_defs, classroom, teacher)
      end

    pairs.each { |mission, rate| assign_mission(mission, rate, students) }
  end

  # Mission + goals 생성만 담당하고 [[mission, completion_rate], …] 를 돌려준다.
  def build_missions(missions, classroom, teacher)
    missions.filter_map do |md|
      next if classroom.missions.exists?(title: md.fetch("title"))

      start_date = Date.current - (md["start_days_ago"] || 21).to_i
      end_date = Date.current + (md["end_days_ahead"] || 14).to_i
      end_date = start_date + 14 if end_date < start_date
      reward = (md["reward_points"] || 30).to_i.clamp(0, Mission.reward_max_points)

      mission = Mission.new(
        classroom:, created_by: teacher, title: md.fetch("title"),
        description: md["description"], start_date:, end_date:,
        reward_points: reward, status: :published, published_at: start_date.to_time
      )
      Array(md.fetch("goals")).each do |gd|
        mission.mission_goals.build(
          goal_type: gd.fetch("type"), target_count: gd.fetch("target").to_i, position: 0
        )
      end
      mission.save!
      @totals[:missions] += 1

      [ mission, (md["completion_rate"] || 0.5).to_f ]
    end
  end

  # 완료 시각은 미션 기간 안으로 클램프한다(짧은 미션에 종료일 넘는 완료가 찍히지 않게).
  # 완료분은 rewarded_at 을 함께 채워 ReevaluateJob 재평가 대상에서 빠진다.
  def assign_mission(mission, rate, students)
    reward = mission.reward_points.to_i
    cutoff = (students.size * rate).round
    window_end = mission.end_date.to_time.end_of_day

    students.each_with_index do |st, idx|
      next if MissionParticipation.exists?(mission_id: mission.id, user_id: st[:user].id)

      explicit_completion = st[:sd].key?("completed_missions")
      completed = if explicit_completion
        Array(st[:sd]["completed_missions"]).map(&:to_s).include?(mission.title)
      else
        idx < cutoff
      end
      assigned_at = mission.start_date.to_time + rand_int(0, 24).hours
      done_at = if completed
        explicit_completion ? [ Time.current, window_end ].min : [ assigned_at + rand_int(1, 10).days, window_end ].min
      end
      participation = MissionParticipation.create!(
        mission:, user: st[:user], assigned_at:,
        completed_at: done_at, rewarded_at: done_at,
        reward_points_awarded: (completed ? reward : 0)
      )
      if explicit_completion && Missions::ProgressCalculator.new(mission, st[:user], participation:).completed? != completed
        raise ArgumentError, "#{st[:user].name}의 '#{mission.title}' 완료 상태가 실제 목표 진행도와 다릅니다"
      end
      st[:mission_points] += reward if completed
      @totals[:mission_participations] += 1
    end
  end

  # ── 토론방 + 토론 글 + 좋아요 ───────────────────────────────────────────
  # peers 를 주면 좋아요 풀을 그 학급 전원으로 넓힌다(top-up 시 기존 학생도 또래로 참여).
  # 토론방은 학급에 이미 있으면 재사용하고 없을 때만 만든다(멱등).
  def seed_topics_and_forum(topic_entries, classroom, students, peers: nil)
    definitions = topic_entries.map.with_index { |entry, index| discussion_topic_definition(entry, index) }
    duplicate_keys = definitions.group_by { |definition| definition.fetch(:key) }.select { |_key, rows| rows.many? }.keys
    raise ArgumentError, "토론 주제 key 중복: #{duplicate_keys.join(', ')}" if duplicate_keys.any?

    topics = Topic.where(classroom:).order(:id).to_a
    if topics.empty?
      return if definitions.empty?

      topics = definitions.map do |definition|
        Topic.create!(
          classroom:,
          scope: :classroom,
          title: definition.fetch(:title),
          kind: definition.fetch(:kind),
          book: discussion_book(definition[:book_title])
        )
      end
      @totals[:topics] += topics.size
    end

    topics_by_key = definitions.to_h do |definition|
      topic = topics.find { |candidate| candidate.title == definition.fetch(:title) }
      if definition[:structured] && topic.nil?
        raise ArgumentError, "구조화 토론 주제를 기존 학급에서 찾을 수 없습니다: #{definition.fetch(:title)}"
      end

      [ definition.fetch(:key), topic || topics.fetch(definition.fetch(:index) % topics.size) ]
    end
    # 레거시 문자열형 글은 입장이 없으므로 찬반 토론방(사용자가 연 것 포함)에는 배정하지 않는다.
    legacy_topics = topics.reject(&:debate?)

    posts = []
    students.each do |st|
      Array(st[:sd]["forum_posts"]).each_with_index do |entry, i|
        structured = entry.is_a?(Hash)
        text = structured ? entry.fetch("text") : entry
        next if text.to_s.strip.length < 2

        topic = if structured
          topics_by_key.fetch(entry.fetch("topic").to_s) do
            raise ArgumentError, "알 수 없는 토론 주제 key: #{entry.fetch('topic')}"
          end
        else
          next if legacy_topics.empty?

          legacy_topics[(st[:user].id + i) % legacy_topics.size]
        end
        # 찬반 토론 글은 검수된 입장(pro/con)을 그대로 저장한다. 레거시 문자열형 글과, 증원 경로가
        # 재사용한 예전 자유 의견 토론방(kind 도입 전 생성)의 글은 입장을 두지 않는다.
        stance = entry["stance"].presence if structured && topic.debate?
        fp = ForumPost.create!(topic:, user: st[:user], text: text.to_s.strip[0, 500], stance:)
        fp.update_columns(created_at: backdate(rand_int(1, 40)))
        posts << fp
        @totals[:forum_posts] += 1
      end
    end

    # 또래 좋아요: 각 글에 저자 외 학생 몇 명이 좋아요.
    users = Array(peers).presence || students.map { |st| st[:user] }
    posts.each do |fp|
      likers = users.reject { |u| u.id == fp.user_id }.shuffle(random: @rng).first(rand_int(0, 6))
      likers.each { |u| ForumPostLike.create!(forum_post: fp, user: u); @totals[:forum_post_likes] += 1 }
    end
  end

  def discussion_topic_definition(entry, index)
    if entry.is_a?(Hash)
      {
        key: entry.fetch("key").to_s,
        title: entry.fetch("title").to_s,
        book_title: entry["book_title"].presence,
        kind: entry["kind"].presence || "free",
        index:,
        structured: true
      }
    else
      { key: index.to_s, title: entry.to_s, book_title: nil, kind: "free", index:, structured: false }
    end
  end

  def discussion_book(title)
    return if title.blank?

    Book.find_by(title:) || Book.where("title LIKE ?", "#{Book.sanitize_sql_like(title)}%").order(:id).first
  end

  # ── 우수작 게시판 + 응원 ─────────────────────────────────────────────────
  def seed_board_and_cheers(students, classroom, peers: nil, featured_report_keys: nil, require_featured_reports: false)
    users = Array(peers).presence || students.map { |st| st[:user] }
    reports = featured_reports_for(
      students,
      featured_report_keys:,
      require_all: require_featured_reports
    )
    reports.each do |report|
      BoardPost.create!(report:)
      report.update_columns(shared: true)
      @totals[:board_posts] += 1

      cheerers = users.reject { |u| u.id == report.user_id }.shuffle(random: @rng).first(rand_int(1, 8))
      cheerers.each do |u|
        Cheer.create!(board_post: report.board_post, user: u)
        @totals[:cheers] += 1
      end
      report.update_columns(cheers_count: cheerers.size)
    end
  end

  # ── 책 소개 대결 / 뒷이야기 이어쓰기 + 투표 ─────────────────────────────
  def seed_social_games(students, classroom, peers: nil, sequel_definitions: nil)
    users = Array(peers).presence || students.map { |st| st[:user] }
    # 정본 목록이 있는 학급은 학생 템플릿의 짧은 book_sequel 문구를 쓰지 않는다. 건너뛴 결과 만들 글이
    # 하나도 없어도(증원 경로) 템플릿 문구로 되돌아가지 않도록 "정본 학급인가"와 "이번에 만들 글"을 나눈다.
    curated_classroom = Array(sequel_definitions).any?
    curated_sequels = seedable_sequel_definitions(Array(sequel_definitions), students, peers)

    students.each_with_index do |st, i|
      if (intro = st[:sd]["book_intro"]).present? && intro.to_s.strip.length >= 10
        written_at = writing_time(st[:user], writing_date(st[:user], "template-intro"))
        bi = BookIntro.create!(user: st[:user], book: pool_book(i + 1), classroom:, body: intro.to_s.strip[0, 1000],
                               created_at: written_at, updated_at: written_at)
        vote_from(users, st[:user]) { |u| BookIntroVote.create!(book_intro: bi, user: u); @totals[:book_intro_votes] += 1 }
        @totals[:book_intros] += 1
      end

      next if curated_classroom
      next unless (seq = st[:sd]["book_sequel"]).present? && seq.to_s.strip.length >= 10

      # 템플릿 학급의 뒷이야기는 모두 담임이 승인한 상태로 둔다(코멘트는 담임 승인 뒤에만 학생에게 보인다).
      # 승인 대기 글을 보여 줄 학급은 정본 book_sequels 에 reviewed: false 로 직접 적는다.
      written_at = writing_time(st[:user], writing_date(st[:user], "template-sequel"))
      reviewed_at = [ written_at + 1.day, Time.current ].min
      bs = BookSequel.create!(
        user: st[:user], book: pool_book(i + 5), classroom:, body: seq.to_s.strip[0, 2000],
        ai_status: :done, ai_comment: GAME_SEQUEL_COMMENT,
        reviewed_at:, reviewed_by: classroom.teacher, created_at: written_at, updated_at: reviewed_at
      )
      vote_from(users, st[:user]) { |u| BookSequelVote.create!(book_sequel: bs, user: u); @totals[:book_sequel_votes] += 1 }
      @totals[:book_sequels] += 1
    end

    seed_curated_book_sequels(curated_sequels, students, classroom, users) if curated_sequels.any?
  end

  # 정본 뒷이야기 중 이번에 만들 것. 증원 경로(peers 가 학급 전원)에서 이미 반에 있던 학생의 글은
  # 건너뛴다 — 기존 학생은 또래로만 참여한다는 증원 계약(기존 학생 명의의 새 활동을 만들지 않는다).
  # 반 어디에도 없는 이름은 정본 오류라 멈춘다.
  def seedable_sequel_definitions(definitions, students, peers)
    new_names = students.map { |st| st[:user].name }.to_set
    existing_names = Array(peers).map(&:name).to_set - new_names

    definitions.select do |definition|
      name = definition.fetch("student_name")
      next true if new_names.include?(name)
      next false if existing_names.include?(name)

      raise ArgumentError, "뒷이야기 작성 학생을 찾을 수 없습니다: #{name}"
    end
  end

  # 정본 뒷이야기는 도우미 코멘트(ai_comment)와 담임 승인 여부(reviewed, 기본 true)까지 YAML 에 적힌 그대로 만든다.
  def seed_curated_book_sequels(definitions, students, classroom, users)
    definitions.each do |definition|
      author = students.find { |st| st[:user].name == definition.fetch("student_name") }&.fetch(:user)
      raise ArgumentError, "뒷이야기 작성 학생을 찾을 수 없습니다: #{definition.fetch('student_name')}" unless author

      book = match_book(definition.fetch("book_title"))
      raise ArgumentError, "뒷이야기 도서를 찾을 수 없습니다: #{definition.fetch('book_title')}" unless book

      body = definition.fetch("body").to_s.strip
      unless body.length.between?(10, 2_000)
        raise ArgumentError, "뒷이야기 본문 길이가 올바르지 않습니다: #{definition.fetch('book_title')}"
      end

      comment = definition["ai_comment"].to_s.strip
      raise ArgumentError, "뒷이야기 도우미 코멘트가 없습니다: #{definition.fetch('book_title')}" if comment.empty?

      reviewed = definition.fetch("reviewed", true)
      # 승인한 글은 다른 글과 같은 날짜 규칙, 담임 검토를 기다리는 글은 막 낸 글이라 가장 최근 며칠.
      key = "curated-#{definition.fetch('book_title')}"
      written_at = writing_time(author, reviewed ? writing_date(author, key) : recent_writing_date(author, key))
      reviewed_at = [ written_at + 1.day, Time.current ].min if reviewed
      sequel = BookSequel.create!(
        user: author, book:, classroom:, body:,
        ai_status: :done, ai_comment: comment,
        reviewed_at:, reviewed_by: (classroom.teacher if reviewed),
        created_at: written_at, updated_at: reviewed_at || written_at
      )
      vote_from(users, author) do |user|
        BookSequelVote.create!(book_sequel: sequel, user:)
        @totals[:book_sequel_votes] += 1
      end
      @totals[:book_sequels] += 1
    end
  end

  # 게임 완료 기록과 같은 책·같은 날의 글. 본문은 책별 예시 글 풀(book_social.yml)에서 온다.
  def write_game_entry!(gtype, user, classroom, book, played_on)
    texts = social_texts.fetch(book.isbn)
    written_at = writing_time(user, played_on)
    case gtype
    when :book
      BookIntro.create!(user:, book:, classroom:, body: texts.fetch("book_intro").to_s.strip[0, 1000],
                        created_at: written_at, updated_at: written_at)
      @totals[:book_intros] += 1
    when :sequel
      reviewed_at = [ written_at + 1.day, Time.current ].min
      BookSequel.create!(user:, book:, classroom:, body: texts.fetch("book_sequel").to_s.strip[0, 2000],
                         ai_status: :done, ai_comment: GAME_SEQUEL_COMMENT,
                         reviewed_at:, reviewed_by: classroom.teacher,
                         created_at: written_at, updated_at: reviewed_at)
      @totals[:book_sequels] += 1
    end
  end

  # 글 쓰는 게임(gtype)의 책 — 그 게임의 예시 글이 있고, 이 학생이 아직 게임하지 않았고(taken), 같은 반에서
  # 같은 게임으로 아직 쓰이지 않은 책(같은 글이 한 반에 두 번 보이지 않게). 없으면 nil.
  def social_book_for(gtype, classroom, index, taken)
    pool = social_book_pool
    return nil if pool.empty?

    used = (@social_books_used ||= Hash.new { |hash, key| hash[key] = Set.new })[[ classroom.id, gtype ]]
    field = gtype == :book ? "book_intro" : "book_sequel"
    pool.size.times do |offset|
      book = pool[(index + offset) % pool.size]
      next if taken.include?(book.id) || used.include?(book.id)
      next if social_texts.dig(book.isbn, field).to_s.strip.length < 10

      used << book.id
      return book
    end
    nil
  end

  # 예시 글이 있는 정식 카탈로그 도서(검색 캐시 제외), id 순.
  def social_book_pool
    @social_book_pool ||= Book.where(isbn: social_texts.keys).where.not(category: :searched).order(:id).to_a
  end

  def social_texts
    @social_texts ||= File.exist?(SOCIAL_TEXTS_PATH) ? YAML.load_file(SOCIAL_TEXTS_PATH) : {}
  end

  # 시드가 만드는 글(책 소개·뒷이야기)의 날짜 규칙 — 1학기(5/1~7/20)에 주로, 9월에 조금(WRITING_SEPTEMBER_SHARE),
  # 8월(여름방학)은 없다. 적재한 순간의 날짜로 찍히면 반 전체 글이 한날에 몰린다.
  # [1학기, 9월] — 오늘 전까지만, 올해 1학기가 아직 오지 않았으면(3~4월에 시드) 지난해 것.
  def writing_ranges
    latest = Date.current - 1
    year = Date.new(latest.year, *WRITING_TERM_START) > latest ? latest.year - 1 : latest.year
    [ Date.new(year, *WRITING_TERM_START)..[ Date.new(year, *WRITING_TERM_END), latest ].min,
      Date.new(year, 9, 1)..[ Date.new(year, 9, 30), latest ].min ]
  end

  # key 는 학생 안에서 글마다 다른 값(게임 순번·"template-intro"·정본 책 제목 등). 학생·key 로 정해지는 난수라
  # 학급 공용 @rng 의 순서를 바꾸지 않는다(다른 시드 결과가 그대로다).
  def writing_date(user, key)
    rng = Random.new(Zlib.crc32("writing-date-#{user.id}-#{key}"))
    term, september = writing_ranges
    range = september.begin <= september.end && rng.rand < WRITING_SEPTEMBER_SHARE ? september : term
    range.begin + rng.rand((range.end - range.begin).to_i + 1)
  end

  # 담임 검토를 기다리는 글은 막 낸 글이라 허용 범위의 가장 최근 며칠(8월은 여기서도 없다).
  def recent_writing_date(user, key)
    rng = Random.new(Zlib.crc32("recent-writing-date-#{user.id}-#{key}"))
    range = writing_ranges.reverse.find { |candidate| candidate.begin <= candidate.end }
    [ range.end - rng.rand(4), range.begin ].max
  end

  # 그날 수업 시간대(09:00~15:59)의 시각.
  def writing_time(user, date)
    date.in_time_zone.change(hour: 9) + ((user.id * 37) % 420).minutes
  end

  # ── 마무리: 포인트/경험치/시즌점수/뱃지 ─────────────────────────────────
  def finalize_student(st)
    user = st[:user]
    total = st[:report_points] + st[:game_points] + st[:mission_points]
    user.update_columns(points: total, experience: total)

    season = SeasonScore.find_or_initialize_by(
      academic_year: Classroom.current_academic_year, user_id: user.id
    )
    season.assign_attributes(
      experience_earned: total, points_earned: total,
      school_id: user.school_id, classroom_id: user.classroom_id, grade: st[:classroom].grade
    )
    season.save!

    user.reload.refresh_badges!
    @totals[:badges] += user.user_badges.count if user.user_badges.exists?
  end

  # ── 헬퍼 ────────────────────────────────────────────────────────────────
  def vote_from(users, author)
    voters = users.reject { |u| u.id == author.id }.shuffle(random: @rng).first(rand_int(1, 7))
    voters.each { |u| yield u }
  end

  # 품질(a/b/c)에 맞는 5축 루브릭 해시(약간의 변주). score_rubric 이 등급을 확정한다.
  def rubric_for(quality)
    case quality
    when "a"
      { content: 5, emotion: rand_int(4, 5), life: rand_int(4, 5), structure: rand_int(4, 5), spelling: rand_int(4, 5) }
    when "c"
      { content: 2, emotion: rand_int(1, 2), life: rand_int(1, 2), structure: rand_int(2, 3), spelling: rand_int(1, 3) }
    else # b
      { content: rand_int(3, 4), emotion: rand_int(3, 4), life: 3, structure: rand_int(3, 4), spelling: rand_int(3, 4) }
    end
  end

  def report_rubric(report_data, quality)
    explicit = report_data["rubric"]
    return rubric_for(quality) unless explicit.is_a?(Hash)

    ReadingDomain::RUBRIC_AXES.index_with { |axis| Integer(explicit.fetch(axis.to_s)) }
  rescue KeyError, ArgumentError, TypeError
    raise ArgumentError, "독후감 rubric은 5축 정수 점수를 모두 포함해야 합니다"
  end

  def report_feedback(report_data, quality)
    explicit = report_data["feedback"]
    explicit.is_a?(Hash) ? explicit : feedback_payload(quality)
  end

  def report_revision_for!(report_data, st)
    parent_key = report_data["revision_of"].presence
    return unless parent_key

    st[:reports_by_seed_key].fetch(parent_key.to_s)
  rescue KeyError
    raise ArgumentError, "고쳐쓰기 원문 seed_key를 먼저 정의해야 합니다: #{parent_key}"
  end

  def register_report_seed_key!(report_data, report, st)
    key = report_data["seed_key"].presence&.to_s
    return unless key
    raise ArgumentError, "학생 안에서 독후감 seed_key가 중복됩니다: #{key}" if st[:reports_by_seed_key].key?(key)

    st[:reports_by_seed_key][key] = report
  end

  def preferred_active_monster!(key)
    return if key.blank?

    MonsterSpecies.find_by(key: key.to_s) || raise(ArgumentError, "활성 몬스터 key를 찾을 수 없습니다: #{key}")
  end

  def monster_dex_nos(lines, salt, preferred)
    return pick_dex_nos(lines, salt) unless preferred

    others = pick_dex_nos(MonsterSpecies::DESIGN_LINE_COUNT, salt).reject { |dex_no| dex_no == preferred.dex_no }
    others.first(lines - 1) + [ preferred.dex_no ]
  end

  def featured_reports_for(students, featured_report_keys:, require_all:)
    if featured_report_keys.nil?
      return students.filter_map { |st| st[:shareable].max_by { |report| report.avg.to_f } }
    end

    reports_by_key = students.each_with_object({}) { |st, index| index.merge!(st[:reports_by_seed_key]) }
    keys = Array(featured_report_keys).map(&:to_s)
    missing = keys - reports_by_key.keys
    if require_all && missing.any?
      raise ArgumentError, "우수작 seed_key를 찾을 수 없습니다: #{missing.join(', ')}"
    end

    keys.filter_map { |key| reports_by_key[key] }
  end

  def feedback_payload(quality)
    praise = [ "인물의 마음을 잘 헤아렸어요.", "책의 장면을 생생하게 떠올려 썼어요.", "자신의 경험과 잘 연결했어요." ]
    fix = [ "느낀 점을 조금 더 자세히 써 볼까요?", "맞춤법을 한 번 더 확인해 보세요.", "문장을 더 짧게 나누면 읽기 쉬워요." ]
    {
      "praise" => praise.shuffle(random: @rng).first(2),
      "fix" => (quality == "a" ? [] : fix.shuffle(random: @rng).first(1)),
      "grow" => [ { "text" => "다음에는 결말을 바꿔 상상해 써 보면 좋겠어요.", "standard_code" => nil } ]
    }
  end

  def pick_dex_nos(count, salt)
    offset = salt % MonsterSpecies::DESIGN_LINE_COUNT
    (1..MonsterSpecies::DESIGN_LINE_COUNT).to_a.rotate(offset).first(count)
  end

  def match_book(title)
    return nil if title.blank?

    key = title.to_s.squish
    @book_by_title ||= {}
    return @book_by_title[key] if @book_by_title.key?(key)

    @book_by_title[key] = Book.where(title: key).order(:id).first
  end

  def pool_book(index)
    book_pool[index % book_pool.size]
  end

  def book_pool
    @book_pool ||= Book.where.not(summary: [ nil, "" ]).where.not(title: [ nil, "" ])
                       .order(:id).limit(400).to_a
  end

  def quiz_pool
    @quiz_pool ||= Quiz.where(published: true).to_a
  end

  def ocr_pick?
    @rng.rand < 0.08
  end

  def rand_int(min, max)
    return min if max <= min

    min + @rng.rand(max - min + 1)
  end

  def backdate(days)
    Time.current - days.to_i.days - @rng.rand(24).hours
  end
end
