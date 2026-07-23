# frozen_string_literal: true

require "yaml"
require "zlib"

# 데모(가상 사용) 데이터 시더 — "이 앱을 많이 사용한 것처럼" 보이는 학급·학생·활동을 만든다.
#
# db/seeds/demo/*.yml (학급별 1파일, Sonnet 에이전트 생성)을 읽어 학생·독후감·게임·몬스터·
# 커뮤니티·미션·시즌점수·뱃지를 **멱등**하게 생성한다. seeds.rb 가 SEED_DEMO=1 + 비production
# 게이트에서만 호출한다(운영에 가짜 아동 데이터 유입 차단).
#
# 멱등성: 학급에 이미 독후감이 있으면 그 학급 전체를 건너뛴다(학급 단위 트랜잭션이라 부분 상태 없음).
# 재실행(SEED_DEMO=1 bin/rails db:seed)은 완성된 학급을 no-op 처리한다.
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

  def initialize(root: Rails.root.join("db/seeds/demo"), io: $stdout)
    @root = root
    @io = io
    @totals = Hash.new(0)
  end

  def call
    files = Dir[File.join(@root, "*.yml")].sort
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

    validate_unique_student_names!(data_sources)

    data_sources.each do |path, data|
      seed_classroom(data, File.basename(path))
    rescue => e
      @io.puts "  [demo] #{File.basename(path)} 실패: #{e.class} #{e.message}"
      raise
    end

    @io.puts "  [demo] 완료: " + @totals.map { |k, v| "#{k}=#{v}" }.join(" ")
  end

  private

  # 신규 데모 학급은 검증된 기존 활동 구성을 템플릿으로 재사용할 수 있다. 템플릿 파일은
  # 학생의 활동량·콘텐츠를 제공하고, 참조 파일은 학교·담임·학생 명단만 선언한다.
  # student_names 는 템플릿의 20명보다 적거나 많아도 된다(현재 18~22명 지원). 인원이
  # 많을 때는 활동 프로필을 순환 재사용하되 학생 이름은 항상 별개로 검증한다. activity_level
  # (high/balanced/low)은 학생 활동과 미션 완료율을 함께 조절해 학급별 사용량 차이를 만든다.
  def load_seed_data(path)
    data = YAML.safe_load_file(path, aliases: false)
    return data unless data["template"].present?

    template_name = data.fetch("template").to_s
    unless template_name.match?(/\A[a-z0-9_]+\.yml\z/)
      raise ArgumentError, "template은 db/seeds/demo 안의 YAML 파일명이어야 합니다"
    end

    template = YAML.safe_load_file(@root.join(template_name), aliases: false)
    names = Array(data.fetch("student_names")).map(&:to_s)
    source_students = template.fetch("students")
    activity_level = data["activity_level"].presence || "high"
    activity_scale = activity_scale_for(activity_level)

    unless names.size.between?(18, 22)
      raise ArgumentError, "student_names는 18명에서 22명 사이여야 합니다"
    end
    if names.any?(&:blank?) || names.uniq.size != names.size
      raise ArgumentError, "student_names에는 비어 있거나 중복된 이름을 넣을 수 없습니다"
    end

    seed_data = template.merge(data.except("template", "student_names", "activity_level"))
    seed_data.merge(
      "missions" => scale_missions(Array(seed_data["missions"]), activity_scale),
      "students" => source_students.cycle.take(names.size).zip(names).map do |student, name|
        scale_student_activity(student, activity_scale).merge("name" => name)
      end
    )
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

    classroom = Classroom.find_by(school_id: school.id, academic_year:, grade:, class_no:)
    if classroom&.reports&.exists?
      @io.puts "  [demo] #{filename}: #{label} #{grade}-#{class_no} 이미 시드됨 — 건너뜀."
      return
    end

    @rng = Random.new(Zlib.crc32("#{school.neis_code}-#{grade}-#{class_no}"))

    ActiveRecord::Base.transaction do
      teacher = seed_teacher(data.fetch("teacher"), school)
      classroom ||= Classroom.create!(school:, academic_year:, grade:, class_no:, teacher:)
      classroom.update!(teacher:) if classroom.teacher_id.nil?

      students = data.fetch("students").map { |sd| seed_student(sd, school, classroom) }

      seed_missions(Array(data["missions"]), classroom, teacher, students)
      seed_topics_and_forum(Array(data["topics"]), classroom, students)
      seed_board_and_cheers(students, classroom)
      seed_social_games(students, classroom)

      students.each { |st| finalize_student(st) }

      @totals[:classrooms] += 1
      @totals[:students] += students.size
      @io.puts "  [demo] #{label} #{grade}-#{class_no}: 학생 #{students.size}명 + 활동 생성"
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

  def seed_student(sd, school, classroom)
    name = sd.fetch("name").to_s
    user = User.find_or_initialize_by(school_id: school.id, classroom_id: classroom.id, name:)
    if user.new_record?
      user.assign_attributes(role: :student, password: STUDENT_PASSWORD)
      user.save!
    end

    st = { user:, sd:, classroom:, report_points: 0, game_points: 0, mission_points: 0,
           reports: [], shareable: [] }

    seed_reports(st)
    seed_games(st)
    seed_monsters(st)
    st
  end

  # ── 독후감 ──────────────────────────────────────────────────────────────
  def seed_reports(st)
    user = st[:user]
    classroom = st[:classroom]
    Array(st[:sd]["reports"]).each do |rd|
      quality = (rd["quality"] || "b").to_s.downcase
      rubric = rubric_for(quality)
      scored = RubricScorable.score_rubric(rubric)
      book = match_book(rd["book_title"])
      reviewed = rd.fetch("reviewed", true) ? true : false
      created = backdate(rd["days_ago"] || rand_int(3, 60))
      input_mode = ocr_pick? ? :ocr : :keyboard
      improvement = rd["improvement"].to_f

      report = Report.new(
        user:, classroom:, book: book, book_title: rd["book_title"],
        body: rd["body"].to_s, input_mode:, ai_status: :done,
        rubric: rubric.merge(feedback_payload(quality)),
        avg: scored[:avg], level: scored[:level],
        points_awarded: (reviewed ? scored[:points] : 0),
        reviewed:, reviewed_at: (reviewed ? created + rand_int(1, 48).hours : nil),
        teacher_comment: rd["teacher_comment"].presence,
        improvement: (improvement.positive? ? improvement : nil),
        shared: false
      )
      report.save!
      report.update_columns(created_at: created, updated_at: created)

      st[:report_points] += report.points_awarded.to_i
      st[:reports] << report
      st[:shareable] << report if reviewed && %w[A B].include?(report.level)
      @totals[:reports] += 1
    end
  end

  # ── 게임(원장 + 퀴즈 시도) ───────────────────────────────────────────────
  def seed_games(st)
    user = st[:user]
    plays = (st[:sd]["game_plays"] || 0).to_i
    plays.times do |i|
      gtype = GAME_TYPES[i % GAME_TYPES.size]
      book = pool_book(i + user.id)
      played_on = (Date.current - (i + 1)).to_s
      GamePlay.create!(user:, game_type: gtype, book: book, played_on: played_on)
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
    dex_nos = pick_dex_nos(lines, user.id)
    first = nil

    dex_nos.each_with_index do |dex_no, idx|
      stage =
        if idx < evolved
          # 진화분: 대부분 stage 2, 일부 stage 3(최종형).
          (idx.even? && idx < (evolved / 2 + 1)) ? 3 : 2
        else
          1
        end
      species = MonsterSpecies.find_by(dex_no:, stage:) || MonsterSpecies.find_by(dex_no:, stage: 1)
      next unless species

      obtained = backdate(rand_int(5, 90))
      um = UserMonster.create!(
        user:, monster_species: species, obtained_at: obtained,
        evolved_at: (stage > 1 ? obtained + rand_int(1, 20).days : nil),
        celebrated_at: obtained, nickname: nil
      )
      first ||= um
      @totals[:user_monsters] += 1
    end

    user.update_columns(active_monster_id: first.id) if first
  end

  # ── 미션 ────────────────────────────────────────────────────────────────
  def seed_missions(missions, classroom, teacher, students)
    missions.each do |md|
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

      rate = (md["completion_rate"] || 0.5).to_f
      cutoff = (students.size * rate).round
      students.each_with_index do |st, idx|
        completed = idx < cutoff
        assigned_at = start_date.to_time + rand_int(0, 24).hours
        mp = MissionParticipation.create!(
          mission:, user: st[:user], assigned_at:,
          completed_at: (completed ? assigned_at + rand_int(1, 10).days : nil),
          rewarded_at: (completed ? assigned_at + rand_int(1, 10).days : nil),
          reward_points_awarded: (completed ? reward : 0)
        )
        st[:mission_points] += reward if completed
        @totals[:mission_participations] += 1
      end
    end
  end

  # ── 토론방 + 토론 글 + 좋아요 ───────────────────────────────────────────
  def seed_topics_and_forum(topic_titles, classroom, students)
    return if topic_titles.empty?

    topics = topic_titles.map.with_index do |title, i|
      Topic.create!(classroom:, scope: :classroom, title: title.to_s, book: pool_book(i + 3))
    end
    @totals[:topics] += topics.size

    posts = []
    students.each do |st|
      Array(st[:sd]["forum_posts"]).each_with_index do |text, i|
        next if text.to_s.strip.length < 2

        topic = topics[(st[:user].id + i) % topics.size]
        fp = ForumPost.create!(topic:, user: st[:user], text: text.to_s.strip[0, 500])
        fp.update_columns(created_at: backdate(rand_int(1, 40)))
        posts << fp
        @totals[:forum_posts] += 1
      end
    end

    # 또래 좋아요: 각 글에 저자 외 학생 몇 명이 좋아요.
    users = students.map { |st| st[:user] }
    posts.each do |fp|
      likers = users.reject { |u| u.id == fp.user_id }.shuffle(random: @rng).first(rand_int(0, 6))
      likers.each { |u| ForumPostLike.create!(forum_post: fp, user: u); @totals[:forum_post_likes] += 1 }
    end
  end

  # ── 우수작 게시판 + 응원 ─────────────────────────────────────────────────
  def seed_board_and_cheers(students, classroom)
    users = students.map { |st| st[:user] }
    students.each do |st|
      report = st[:shareable].max_by { |r| r.avg.to_f }
      next unless report

      BoardPost.create!(report:)
      report.update_columns(shared: true)
      @totals[:board_posts] += 1

      cheerers = users.reject { |u| u.id == st[:user].id }.shuffle(random: @rng).first(rand_int(1, 8))
      cheerers.each do |u|
        Cheer.create!(board_post: report.board_post, user: u)
        @totals[:cheers] += 1
      end
      report.update_columns(cheers_count: cheerers.size)
    end
  end

  # ── 책 소개 대결 / 뒷이야기 이어쓰기 + 투표 ─────────────────────────────
  def seed_social_games(students, classroom)
    users = students.map { |st| st[:user] }

    students.each_with_index do |st, i|
      if (intro = st[:sd]["book_intro"]).present? && intro.to_s.strip.length >= 10
        bi = BookIntro.create!(user: st[:user], book: pool_book(i + 1), classroom:, body: intro.to_s.strip[0, 1000])
        vote_from(users, st[:user]) { |u| BookIntroVote.create!(book_intro: bi, user: u); @totals[:book_intro_votes] += 1 }
        @totals[:book_intros] += 1
      end

      next unless (seq = st[:sd]["book_sequel"]).present? && seq.to_s.strip.length >= 10

      bs = BookSequel.create!(
        user: st[:user], book: pool_book(i + 5), classroom:, body: seq.to_s.strip[0, 2000],
        ai_status: :done, ai_comment: "상상력이 돋보이는 이야기예요! 인물의 마음을 잘 이어 썼어요."
      )
      vote_from(users, st[:user]) { |u| BookSequelVote.create!(book_sequel: bs, user: u); @totals[:book_sequel_votes] += 1 }
      @totals[:book_sequels] += 1
    end
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
