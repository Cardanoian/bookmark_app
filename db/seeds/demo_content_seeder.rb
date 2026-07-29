# frozen_string_literal: true

require "yaml"
require "zlib"

# 체험(데모) 계정 추가 콘텐츠 시더 — db/seeds/demo_content.yml 을 읽어 세 가지를 멱등 생성한다.
#
#   ① 담임 김지은의 학급 독서 퀴즈(Quiz origin=teacher·scope=classroom·published, 문항 source=manual)
#   ② 학생 이도현의 문제 기여(QuizContribution). approved 는 담임 승인까지 재현해
#      Games::ContributionPublisher 가 전국 공유 풀(system·global·band)로 물질화하고, pending 은
#      담임 검토 큐에 남는다 — 화면상 "검토 대기 중인 학생 문제"도 함께 보이게 하려는 의도다.
#   ③ 우수작 게시판(BoardPost) + 응원(Cheer). **새 독후감을 만들지 않고** 이미 담임 승인이 끝난
#      A등급 독후감 중 아직 게시판에 없는 글만 골라 올리므로 포인트·통계와 어긋나지 않는다.
#
# 멱등성: 같은 제목의 교사 퀴즈·같은 내용의 기여·이미 게시된 독후감은 다시 만들지 않는다. 응원도
# 이미 응원 수가 채워진 게시물은 건드리지 않는다. 재실행(rake demo_content:seed)은 no-op 이다.
#
# 계정 부재 시 동작: 김지은·이도현·3-1 학급이 없는 DB(데모 데이터를 넣지 않은 실제 운영 배포)에서는
# 해당 블록을 조용히 건너뛴다 — 이 시더 자체가 게이트 역할을 하므로 운영에 가짜 데이터가 새지 않는다.
#
# 선행 태스크와의 관계(주의): 승인 기여가 만드는 풀 퀴즈는 origin=system 이라, 여기 담은 도서가 나중에
# `db/seeds/book_quizzes.yml` 에 **처음** 추가되면 `books:seed_quizzes` 의 은퇴 로직이 그 퀴즈를 지운다.
# 이 시더의 멱등 판정은 QuizContribution 행 기준이라 재실행해도 되살리지 않으므로, 그 도서를 큐레이션에
# 편입할 때는 demo_content.yml 의 해당 항목도 함께 정리할 것.
class DemoContentSeeder
  def initialize(path: Rails.root.join("db/seeds/demo_content.yml"), io: $stdout)
    @path = path
    @io = io
    @totals = Hash.new(0)
  end

  def call
    unless File.exist?(@path)
      @io.puts "  [demo-content] #{@path} 없음 — 건너뜀."
      return
    end

    @data = YAML.safe_load_file(@path, aliases: false)
    raise "demo_content.yml 은 매핑이어야 합니다" unless @data.is_a?(Hash)

    seed_teacher_quizzes
    seed_student_contributions
    seed_featured_reports

    @io.puts "  [demo-content] 완료: " + @totals.map { |k, v| "#{k}=#{v}" }.join(" ")
  end

  private

  # ── 계정·도서 조회 ────────────────────────────────────────────────────────
  def teacher
    return @teacher if defined?(@teacher)

    email = @data.dig("teacher", "email").to_s.downcase
    @teacher = User.find_by(email: email, role: :teacher)
  end

  # 담임이 맡은 학급 중 현재 학년도의 학급(샘플 3-1). 퀴즈의 소속 학급이자 학생 조회 범위다.
  def classroom
    return @classroom if defined?(@classroom)

    @classroom =
      if teacher
        Classroom.where(teacher_id: teacher.id)
                 .order(Arel.sql("academic_year DESC"), :grade, :class_no).first
      end
  end

  def student
    return @student if defined?(@student)

    name = @data.dig("student", "name").to_s
    @student = classroom && User.find_by(classroom_id: classroom.id, role: :student, name: name)
  end

  # 카탈로그 도서만(검색 캐시 제외). ISBN 은 저장 경계와 같은 방식으로 정규화해 매칭 누락을 막는다.
  def find_book(raw_isbn)
    isbn = Books::Isbn.normalize(raw_isbn.to_s) || raw_isbn.to_s
    Book.where.not(category: :searched).find_by(isbn: isbn)
  end

  # ── ① 담임 독서 퀴즈 ──────────────────────────────────────────────────────
  def seed_teacher_quizzes
    entries = Array(@data["teacher_quizzes"])
    return if entries.empty?

    unless teacher && classroom
      @io.puts "  [demo-content] 담임/학급 없음 — 교사 퀴즈 건너뜀."
      return
    end

    band = ReadingDomain.band_for(classroom.grade)

    entries.each do |entry|
      book = find_book(entry["isbn"])
      if book.nil?
        @io.puts "  [demo-content] 도서 미매칭(#{entry['isbn']}) — '#{entry['title']}' 퀴즈 건너뜀."
        @totals[:quizzes_skipped] += 1
        next
      end

      quiz = Quiz.find_or_initialize_by(
        title: entry.fetch("title"), created_by_id: teacher.id, classroom_id: classroom.id
      )
      created = quiz.new_record?
      quiz.book = book
      quiz.scope = :classroom
      quiz.published = true
      quiz.origin = :teacher
      quiz.content_axis = :mcq
      quiz.band = band
      quiz.content_version = 1
      quiz.generation_status = :ready
      quiz.save!

      if quiz.quiz_questions.none?
        Array(entry["questions"]).each_with_index do |q, index|
          choices = Array(q.fetch("choices")).map(&:to_s)
          quiz.quiz_questions.create!(
            question_type: :mcq_single,
            source: :manual,
            position: index + 1,
            prompt: q.fetch("prompt").to_s,
            choices: choices,
            answer_index: q.fetch("answer_index").to_i,
            content: { "prompt" => q.fetch("prompt").to_s, "choices" => choices },
            answer: q.fetch("answer_index").to_i,
            explanation: q["explanation"].to_s,
            difficulty: q["difficulty"]
          )
          @totals[:quiz_questions] += 1
        end
      end

      @totals[created ? :quizzes : :quizzes_existing] += 1
    end
  end

  # ── ② 학생 문제 기여 ──────────────────────────────────────────────────────
  def seed_student_contributions
    entries = Array(@data["student_contributions"])
    return if entries.empty?

    unless student && classroom
      @io.puts "  [demo-content] 체험 학생 없음 — 학생 기여 건너뜀."
      return
    end

    band = ReadingDomain.game_band_for(classroom.grade)

    entries.each do |entry|
      book = find_book(entry["isbn"])
      if book.nil?
        @totals[:contributions_skipped] += 1
        next
      end

      axis = entry.fetch("content_axis").to_s
      payload = stringify(entry.fetch("payload"))
      if contribution_exists?(book, axis, payload)
        @totals[:contributions_existing] += 1
        next
      end

      contribution = QuizContribution.new(
        user: student, book: book, classroom: classroom,
        content_axis: axis, band: band, payload: payload
      )

      if entry["status"].to_s == "approved"
        contribution.status = :approved
        contribution.reviewed_by = teacher
        ApplicationRecord.transaction do
          contribution.save!
          Games::ContributionPublisher.publish!(contribution)
        end
        @totals[:contributions_approved] += 1
      else
        contribution.status = :pending
        contribution.save!
        @totals[:contributions_pending] += 1
      end
    end
  end

  # 같은 학생·도서·축에 같은 문항(mcq=질문 / hint_reveal=정답)이 이미 있는지. 재실행 중복 방지.
  def contribution_exists?(book, axis, payload)
    key = axis == "mcq" ? "prompt" : "answer"
    value = payload[key].to_s
    QuizContribution.where(user_id: student.id, book_id: book.id, content_axis: axis).any? do |existing|
      existing.payload_hash[key].to_s == value
    end
  end

  # ── ③ 우수작 게시판 + 응원 ────────────────────────────────────────────────
  def seed_featured_reports
    config = @data["featured_reports"]
    return unless config.is_a?(Hash)

    cheer_min = config.fetch("cheer_min", 4).to_i
    cheer_max = [ config.fetch("cheer_max", 12).to_i, cheer_min ].max

    # **선택은 게시 여부와 무관한 규칙으로 먼저 확정**하고, 그중 아직 게시되지 않은 글만 올린다.
    # 남은 후보에서 매번 새로 뽑으면 재실행할 때마다 우수작이 계속 늘어나므로(멱등 위반) 순서가 중요하다.
    picks = student_picks(config.fetch("student_pick_count", 5).to_i)
    picks += peer_picks(config.fetch("peer_pick_count", 25).to_i, exclude_ids: picks.map(&:id))

    picks.each do |report|
      if report.board_post
        @totals[:board_posts_existing] += 1
        next
      end

      BoardPost.create!(report: report)
      report.update_columns(shared: true)
      @totals[:board_posts] += 1
      add_cheers(report, cheer_min, cheer_max)
    end
  end

  # 체험 학생(이도현)의 승인 A등급 독후감. 같은 책이 여러 편이면 점수 높은 한 편만 고른다.
  def student_picks(count)
    return [] if student.nil? || count <= 0

    shareable_scope.where(user_id: student.id)
                   .group_by { |r| r.book_title.to_s }
                   .map { |_title, group| group.first }
                   .sort_by { |r| [ -r.avg.to_f, r.id ] }
                   .first(count)
  end

  # 다른 학생들의 승인 A등급 독후감. 학생마다 **최고작 다음 글(2순위)**만 후보로 삼는다 —
  # 학생별 최고작은 DemoSeeder 가 이미 게시판에 올렸으므로 후보가 겹치지 않고, 이 규칙 자체가
  # board_post 유무를 보지 않아 재실행해도 같은 집합이 뽑힌다.
  def peer_picks(count, exclude_ids:)
    return [] if count <= 0

    shareable_scope.where.not(user_id: student&.id || 0)
                   .group_by(&:user_id)
                   .filter_map { |_user_id, group| group[1] }
                   .sort_by { |r| [ -r.avg.to_f, r.id ] }
                   .reject { |r| exclude_ids.include?(r.id) }
                   .first(count)
  end

  # 게시 후보 모집단: 제출·담임 승인까지 끝난 A등급 독후감(점수·id 순). 게시 여부는 보지 않는다.
  def shareable_scope
    Report.submitted.where(reviewed: true, level: "A").order(Arel.sql("avg DESC"), :id)
  end

  # 같은 학급 친구들이 누른 응원. 글마다 결정적(report.id 시드)이라 어느 DB 에서 돌려도 같은 결과다.
  def add_cheers(report, cheer_min, cheer_max)
    peers = User.where(classroom_id: report.classroom_id, role: :student)
                .where.not(id: report.user_id).order(:id).to_a
    return if peers.empty?

    rng = Random.new(Zlib.crc32("cheer-#{report.id}"))
    wanted = cheer_min + rng.rand(cheer_max - cheer_min + 1)
    cheerers = peers.shuffle(random: rng).first([ wanted, peers.size ].min)

    cheerers.each do |user|
      Cheer.create!(board_post: report.board_post, user: user)
      @totals[:cheers] += 1
    end
    report.update_columns(cheers_count: cheerers.size)
  end

  # YAML 로 읽은 페이로드를 JSON 컬럼에 저장할 문자열 키 해시로 정규화한다.
  def stringify(value)
    case value
    when Hash then value.to_h { |k, v| [ k.to_s, stringify(v) ] }
    when Array then value.map { |v| stringify(v) }
    else value
    end
  end
end
