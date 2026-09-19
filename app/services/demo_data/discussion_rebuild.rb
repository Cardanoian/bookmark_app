# frozen_string_literal: true

require "stringio"
require Rails.root.join("db/seeds/demo_seeder").to_s

module DemoData
  # 찬반 토론(2026-09-19) 도입 뒤, 이미 적재된 데모 학급의 토론을 현재 시드 정본으로 되돌리는 일회성 운영 정비.
  # 대상은 시드 정의에 찬반 토론 주제(kind: debate)가 있는 학급이고, 그 학급의 토론방·글·좋아요·신고만
  # 지우고 다시 만든다(학생·독후감·게임·몬스터·미션 같은 다른 활동은 그대로 둔다).
  # 공개 체험 3-1 을 통째로 되돌리는 PublicClassroomRefresh 와 같은 이중 가드·백업·결과 검증을 쓴다.
  class DiscussionRebuild
    CONFIRMATION = "REBUILD_DEMO_DISCUSSIONS_2026"
    SEED_ROOT = Rails.root.join("db/seeds/demo")

    class SafetyError < StandardError; end

    def initialize(io: $stdout, confirmation: nil, backup_database: true, only_files: nil)
      @io = io
      @confirmation = confirmation
      @backup_database = backup_database
      @only_files = only_files
    end

    def preview
      targets.map { |target| target_preview(target) }
    end

    def call!
      validate_execution!
      before = preview
      validate_targets!(before)
      backup = @backup_database ? DatabaseBackup.call!(label: "discussion-rebuild", io: @io, error_class: SafetyError) : nil

      ApplicationRecord.transaction do
        targets.each { |target| seeder.reseed_discussions!(target[:filename], classroom_for(target)) }
        after = preview
        validate_result!(after)
        validate_foreign_keys!
        @io.puts "  [discussion-rebuild] 완료: " + after.map { |row| "#{row[:file]} 글 #{row[:posts]}" }.join(", ")
        { before:, after:, backup: }
      end
    end

    private

    def validate_execution!
      unless ENV["DEMO_DEPLOYMENT"] == "1"
        raise SafetyError, "DEMO_DEPLOYMENT=1인 심사·시연 인스턴스에서만 실행할 수 있습니다"
      end
      return if @confirmation == CONFIRMATION

      raise SafetyError, "CONFIRM=#{CONFIRMATION} 확인 문자열이 필요합니다"
    end

    # 대상 학급이 모두 있고, 검증된 가상 학교에 있으며, 학생 명단이 시드와 정확히 같을 때만 지운다.
    def validate_targets!(rows)
      raise SafetyError, "찬반 토론을 정의한 시드 학급이 없습니다" if rows.empty?

      rows.each do |row|
        raise SafetyError, "#{row[:file]}: 대상 학급을 찾을 수 없습니다" unless row[:found]
        raise SafetyError, "#{row[:file]}: 검증된 가상 학교가 아닙니다" unless row[:manual_school]
        next if row[:missing_students].zero? && row[:unexpected_students].zero?

        raise SafetyError, "#{row[:file]}: 학생 명단이 시드와 다릅니다" \
                           "(missing=#{row[:missing_students]}, extras=#{row[:unexpected_students]})"
      end
    end

    def validate_result!(rows)
      rows.each do |row|
        next if row[:topics_match] && row[:kinds_match] && row[:posts] == row[:expected_posts] && row[:stances_match]

        raise SafetyError, "#{row[:file]}: 재적재 결과가 시드와 다릅니다: #{row.inspect}"
      end
    end

    def validate_foreign_keys!
      return unless ApplicationRecord.connection.adapter_name == "SQLite"

      violations = ApplicationRecord.connection.execute("PRAGMA foreign_key_check")
      raise SafetyError, "외래키 위반 #{violations.size}건이 발생했습니다" if violations.any?
    end

    def target_preview(target)
      classroom = classroom_for(target)
      return { file: target[:filename], found: false } unless classroom

      names = classroom.users.where(role: :student).pluck(:name)
      expected_names = target[:data].fetch("students").map { |student| student.fetch("name").to_s }
      topics = Topic.where(classroom_id: classroom.id)
      posts = ForumPost.where(topic_id: topics.select(:id))
      # 책 토론방(book_discussions, 자유 의견) 글은 입장이 없다.
      expected_stances = expected_posts(target).to_h { |post| [ post.fetch("text").to_s.strip, post["stance"] ] }
      expected_kinds = target[:data].fetch("topics").to_h { |topic| [ topic.fetch("title"), topic["kind"].presence || "free" ] }
      actual_stances = posts.pluck(:text, :stance).to_h

      {
        file: target[:filename],
        found: true,
        classroom_id: classroom.id,
        manual_school: classroom.school.data_source == "manual",
        missing_students: (expected_names - names).size,
        unexpected_students: (names - expected_names).size,
        topics: topics.count,
        debate_topics: topics.where(kind: :debate).count,
        expected_topics: target[:data].fetch("topics").size,
        topics_match: topics.pluck(:title).sort == target[:data].fetch("topics").map { |topic| topic.fetch("title") }.sort,
        # 논제는 찬반 토론, 책 토론방(《책》 이야기)은 자유 의견 — 주제마다 시드가 정한 방식 그대로인지.
        kinds_match: topics.exists? && topics.pluck(:title, :kind).to_h == expected_kinds,
        posts: posts.count,
        expected_posts: expected_stances.size,
        stanced_posts: posts.where.not(stance: nil).count,
        stances_match: actual_stances == expected_stances,
        hidden_posts: posts.where(hidden: true).count,
        reported_posts: posts.where("reports_count > 0").count
      }
    end

    def expected_posts(target)
      target[:data].fetch("students").flat_map { |student| Array(student["forum_posts"]) }
                   .select { |post| post.is_a?(Hash) && post.fetch("text").to_s.strip.length >= 2 }
    end

    def targets
      @targets ||= seed_filenames.filter_map do |filename|
        data = seeder.seed_data_for(filename)
        next unless Array(data["topics"]).any? { |topic| topic.is_a?(Hash) && topic["kind"] == "debate" }

        { filename:, data: }
      end
    end

    def seed_filenames
      names = Dir[SEED_ROOT.join("*.yml")].map { |path| File.basename(path) }.sort - [ "schools.yml" ]
      @only_files ? names & @only_files : names
    end

    def classroom_for(target)
      cr = target[:data].fetch("classroom")
      school = School.find_by(neis_code: cr.fetch("school_neis_code").to_s)
      return unless school

      Classroom.find_by(
        school_id: school.id,
        academic_year: (cr["academic_year"] || Classroom.current_academic_year).to_i,
        grade: cr.fetch("grade").to_i,
        class_no: cr.fetch("class_no").to_i
      )
    end

    def seeder
      @seeder ||= DemoSeeder.new(root: SEED_ROOT, io: StringIO.new)
    end
  end
end
