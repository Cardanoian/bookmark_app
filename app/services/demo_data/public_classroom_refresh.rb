# frozen_string_literal: true

require "stringio"
require "yaml"
require Rails.root.join("db/seeds/demo_seeder").to_s
require Rails.root.join("db/seeds/demo_content_seeder").to_s

module DemoData
  # 공개 체험 계정이 사용하는 가상 학급을 검수된 시드 상태로 한 번만 되돌리는 운영 서비스.
  # 세션별 복제나 주기 실행용이 아니며, 대상 학급·학생 명단·확인 문자열을 모두 검증한 뒤에만 쓴다.
  class PublicClassroomRefresh
    CONFIRMATION = "REBUILD_PUBLIC_DEMO_2026"
    SEED_FILENAME = "sample_6_1.yml"
    SEED_ROOT = Rails.root.join("db/seeds/demo")
    ACCOUNTS_PATH = Rails.root.join("db/seeds/accounts.yml")

    class SafetyError < StandardError; end

    def initialize(io: $stdout, confirmation: nil, backup_database: true, demo_seed: nil, content_seed: nil,
                   validate_story: true)
      @io = io
      @confirmation = confirmation
      @backup_database = backup_database
      @validate_story = validate_story
      @demo_seed = demo_seed || -> { DemoSeeder.new(root: SEED_ROOT, io: @io, only_files: [ SEED_FILENAME ]).call }
      @content_seed = content_seed || -> { DemoContentSeeder.new(io: @io).call }
    end

    def preview
      classroom = target_classroom
      return missing_target_preview unless classroom

      student_ids = students(classroom).pluck(:id)
      reports = Report.where(user_id: student_ids)
      {
        target_found: true,
        school_id: classroom.school_id,
        classroom_id: classroom.id,
        expected_students: expected_student_names.size,
        students: student_ids.size,
        unexpected_students: unexpected_student_names(classroom).size,
        missing_students: missing_student_names(classroom).size,
        expected_reports: expected_report_count,
        reports: reports.count,
        excess_reports: reports.count - expected_report_count,
        drafts: reports.where(submitted_at: nil).count,
        expected_unreviewed_reports: expected_unreviewed_report_count,
        unreviewed_reports: reports.where(reviewed: false).count,
        blank_reports: reports.where(body: [ nil, "" ]).count,
        short_reports: reports.where("LENGTH(TRIM(body)) < 20").count,
        forum_posts: ForumPost.where(user_id: student_ids).count,
        book_intros: BookIntro.where(user_id: student_ids).count,
        book_sequels: BookSequel.where(user_id: student_ids).count,
        featured_reports: BoardPost.joins(:report).where(reports: { classroom_id: classroom.id }).count,
        classroom_quizzes: Quiz.where(classroom_id: classroom.id).count,
        quiz_contributions: QuizContribution.where(classroom_id: classroom.id).count
      }.merge(story_preview(classroom))
    end

    def call!
      validate_execution!
      classroom = target_classroom
      raise SafetyError, "공개 체험 학급을 찾을 수 없습니다" unless classroom

      validate_identity!(classroom)
      before = preview
      backup = backup_database!

      ApplicationRecord.transaction do
        purge_activity!(classroom)
        reset_accounts!(classroom)
        @demo_seed.call
        @content_seed.call
        validate_result!
        validate_foreign_keys!
      end

      after = preview
      @io.puts "  [demo-refresh] 완료: reports #{before[:reports]}→#{after[:reports]}, " \
               "drafts #{before[:drafts]}→#{after[:drafts]}, sequels #{before[:book_sequels]}→#{after[:book_sequels]}"
      { before:, after:, backup: }
    end

    private

    def validate_execution!
      unless ENV["DEMO_DEPLOYMENT"] == "1"
        raise SafetyError, "DEMO_DEPLOYMENT=1인 심사·시연 인스턴스에서만 실행할 수 있습니다"
      end
      return if @confirmation == CONFIRMATION

      raise SafetyError, "CONFIRM=#{CONFIRMATION} 확인 문자열이 필요합니다"
    end

    def validate_identity!(classroom)
      school = classroom.school
      unless school.neis_code == seed_classroom.fetch("school_neis_code").to_s && school.data_source == "manual"
        raise SafetyError, "대상이 검증된 가상 학교가 아닙니다"
      end

      extras = unexpected_student_names(classroom)
      missing = missing_student_names(classroom)
      if extras.any? || missing.any?
        raise SafetyError, "학생 명단이 시드와 다릅니다(extras=#{extras.size}, missing=#{missing.size})"
      end

      teacher_email = seed_definition.dig("teacher", "email").to_s.downcase
      return if classroom.teacher&.email.to_s.downcase == teacher_email

      raise SafetyError, "담임 계정이 시드 정의와 다릅니다"
    end

    def purge_activity!(classroom)
      student_ids = students(classroom).pluck(:id)

      # 부모를 destroy해 첨부 파일·카운터 캐시·자식 레코드까지 정상 콜백으로 정리한다.
      Report.where(user_id: student_ids).find_each(&:destroy!)
      Topic.where(classroom_id: classroom.id).find_each(&:destroy!)
      ForumPost.where(user_id: student_ids).find_each(&:destroy!)
      BookIntro.where(user_id: student_ids).find_each(&:destroy!)
      BookSequel.where(user_id: student_ids).find_each(&:destroy!)
      Mission.where(classroom_id: classroom.id).find_each(&:destroy!)
      Quiz.where(classroom_id: classroom.id).find_each(&:destroy!)

      # 다른 범위의 글·퀴즈에 남긴 체험 학생의 반응과 개인 진행도도 함께 초기 상태로 되돌린다.
      Cheer.where(user_id: student_ids).delete_all
      ForumPostLike.where(user_id: student_ids).delete_all
      ForumPostReport.where(user_id: student_ids).delete_all
      BookIntroVote.where(user_id: student_ids).delete_all
      BookSequelVote.where(user_id: student_ids).delete_all
      Sticker.where(by_user_id: student_ids).delete_all
      QuizReport.where(user_id: student_ids).delete_all
      QuizAttempt.where(user_id: student_ids).delete_all
      GamePlay.where(user_id: student_ids).delete_all
      MissionParticipation.where(user_id: student_ids).delete_all
      ChallengeParticipation.where(user_id: student_ids).delete_all
      LearnWizardProgress.where(user_id: student_ids).delete_all
      SeasonScore.where(user_id: student_ids).delete_all
      UserBadge.where(user_id: student_ids).delete_all

      students(classroom).update_all(active_monster_id: nil, points: 0, experience: 0)
      UserMonster.where(user_id: student_ids).delete_all

      # 사서 체험 화면의 학교 범위 자료는 이 가상 학교 전용이므로 정본으로 다시 만든다.
      LibraryLoan.where(school_id: classroom.school_id).delete_all
      LibraryEvent.where(school_id: classroom.school_id).delete_all
    end

    def reset_accounts!(classroom)
      ranking_count = seed_definition.fetch("students").size / 2
      seed_definition.fetch("students").each_with_index do |student_data, index|
        user = students(classroom).find_by!(name: student_data.fetch("name").to_s)
        user.assign_attributes(
          nickname: student_data.fetch("nickname"),
          ranking_opted_in: student_data.fetch("ranking_opted_in", index < ranking_count),
          suspended: false,
          password: DemoSeeder::STUDENT_PASSWORD
        )
        user.save!
      end

      sample_accounts.fetch("users").each do |account|
        next if account.fetch("role") == "student"

        user = User.find_by!(email: account.fetch("email").to_s.downcase)
        unless user.school_id == classroom.school_id && user.role == account.fetch("role")
          raise SafetyError, "체험 교직원 계정 범위가 시드 정의와 다릅니다"
        end

        user.update!(name: account.fetch("name"), suspended: false, password: account.fetch("password"))
      end
    end

    def validate_result!
      result = preview
      unless result[:target_found] && result[:students] == result[:expected_students] &&
             result[:reports] == result[:expected_reports] && result[:drafts].zero? &&
             result[:blank_reports].zero? && result[:short_reports].zero?
        raise SafetyError, "재적재 결과가 시드 품질 기준을 충족하지 못했습니다: #{result.inspect}"
      end

      validate_story_result!(result) if @validate_story
    end

    def validate_story_result!(result)
      valid = result[:story_student_found] &&
              result[:story_reports] == result[:expected_story_reports] &&
              result[:story_revisions] == result[:expected_story_revisions] &&
              result[:story_revision_growth] && result[:story_feedback_visible] &&
              result[:featured_reports] == result[:expected_featured_reports] &&
              result[:story_featured_reports] == result[:expected_featured_reports] &&
              result[:story_completed_missions] == result[:expected_completed_missions] &&
              result[:story_mission_progress_consistent] &&
              result[:story_active_monster_key] == result[:expected_active_monster_key] &&
              result[:story_monster_evolvable] &&
              result[:unreviewed_reports] == result[:expected_unreviewed_reports] &&
              result[:role_report_counts_match]
      return if valid

      raise SafetyError, "대표 체험 이야기 검증에 실패했습니다: #{result.inspect}"
    end

    def validate_foreign_keys!
      return unless ApplicationRecord.connection.adapter_name == "SQLite"

      violations = ApplicationRecord.connection.execute("PRAGMA foreign_key_check")
      raise SafetyError, "외래키 위반 #{violations.size}건이 발생했습니다" if violations.any?
    end

    def backup_database!
      return unless @backup_database

      DatabaseBackup.call!(label: "public-demo-refresh", io: @io, error_class: SafetyError)
    end

    def target_classroom
      cr = seed_classroom
      school = School.find_by(neis_code: cr.fetch("school_neis_code").to_s)
      return unless school

      Classroom.find_by(
        school_id: school.id,
        academic_year: cr.fetch("academic_year").to_i,
        grade: cr.fetch("grade").to_i,
        class_no: cr.fetch("class_no").to_i
      )
    end

    def students(classroom)
      User.where(classroom_id: classroom.id, role: :student)
    end

    def unexpected_student_names(classroom)
      students(classroom).pluck(:name) - expected_student_names
    end

    def missing_student_names(classroom)
      expected_student_names - students(classroom).pluck(:name)
    end

    def seed_definition
      @seed_definition ||= DemoSeeder.new(root: SEED_ROOT, io: StringIO.new).seed_data_for(SEED_FILENAME)
    end

    def seed_classroom
      seed_definition.fetch("classroom")
    end

    def expected_student_names
      @expected_student_names ||= seed_definition.fetch("students").map { |data| data.fetch("name").to_s }
    end

    def expected_report_count
      @expected_report_count ||= seed_definition.fetch("students").sum { |data| Array(data["reports"]).size }
    end

    def expected_unreviewed_report_count
      @expected_unreviewed_report_count ||= seed_definition.fetch("students").sum do |data|
        Array(data["reports"]).count { |report| !report.fetch("reviewed", true) }
      end
    end

    def story_preview(classroom)
      student = students(classroom).find_by(name: story_student_name)
      return missing_story_preview unless student

      reports = Report.submitted.where(user_id: student.id)
      timeline = StudentGrowthTimeline.new(student)
      latest = timeline.latest
      previous = timeline.previous
      revision_growth = latest.present? && previous.present? &&
                        latest.report.revision_of_id == previous.report.id &&
                        timeline.changes.values.all?(&:positive?)
      participations = student.mission_participations.includes(mission: { mission_goals: :books }).to_a
      mission_progress_consistent = participations.all? do |participation|
        completed = Missions::ProgressCalculator.new(
          participation.mission,
          student,
          participation:
        ).completed?
        recorded = participation.completed_at.present? && participation.rewarded_at.present? &&
                   participation.reward_points_awarded == participation.mission.reward_points
        completed == recorded
      end
      active_monster = student.active_monster
      classroom_reports = Report.where(classroom_id: classroom.id)
      submitted_classroom_reports = Report.submitted.where(classroom_id: classroom.id)

      {
        story_student_found: true,
        expected_story_reports: expected_story_report_count,
        story_reports: reports.count,
        expected_story_revisions: expected_story_revision_count,
        story_revisions: reports.where.not(revision_of_id: nil).count,
        story_revision_growth: revision_growth,
        story_feedback_visible: latest&.report&.feedback_visible? && previous&.report&.feedback_visible?,
        expected_featured_reports: expected_featured_report_count,
        story_featured_reports: BoardPost.joins(:report).where(reports: { user_id: student.id }).count,
        expected_completed_missions: expected_completed_mission_count,
        story_completed_missions: participations.count { |participation| participation.completed_at.present? },
        story_mission_progress_consistent: mission_progress_consistent,
        expected_active_monster_key: expected_active_monster_key,
        story_active_monster_key: active_monster&.species&.key,
        story_monster_evolvable: active_monster&.evolvable? || false,
        role_report_counts_match: classroom_reports.count == expected_report_count &&
                                  submitted_classroom_reports.count == expected_report_count &&
                                  classroom_reports.where(reviewed: false).count == expected_unreviewed_report_count
      }
    end

    def missing_story_preview
      {
        story_student_found: false,
        expected_story_reports: expected_story_report_count,
        story_reports: 0,
        expected_story_revisions: expected_story_revision_count,
        story_revisions: 0,
        story_revision_growth: false,
        story_feedback_visible: false,
        expected_featured_reports: expected_featured_report_count,
        story_featured_reports: 0,
        expected_completed_missions: expected_completed_mission_count,
        story_completed_missions: 0,
        story_mission_progress_consistent: false,
        expected_active_monster_key: expected_active_monster_key,
        story_active_monster_key: nil,
        story_monster_evolvable: false,
        role_report_counts_match: false
      }
    end

    def story_definition
      @story_definition ||= seed_definition.fetch("story")
    end

    def story_student_name
      story_definition.fetch("student_name").to_s
    end

    def story_student_definition
      @story_student_definition ||= seed_definition.fetch("students").find do |data|
        data.fetch("name").to_s == story_student_name
      end || raise(SafetyError, "대표 체험 학생이 시드 명단에 없습니다")
    end

    def expected_story_report_count
      Array(story_student_definition["reports"]).size
    end

    def expected_story_revision_count
      Array(story_student_definition["reports"]).count { |report| report["revision_of"].present? }
    end

    def expected_featured_report_count
      Array(story_definition["featured_report_keys"]).size
    end

    def expected_completed_mission_count
      Array(story_student_definition["completed_missions"]).size
    end

    def expected_active_monster_key
      story_student_definition.fetch("active_monster_key").to_s
    end

    def sample_accounts
      @sample_accounts ||= YAML.safe_load_file(ACCOUNTS_PATH, aliases: false).fetch("sample_accounts")
    end

    def missing_target_preview
      {
        target_found: false,
        expected_students: expected_student_names.size,
        expected_reports: expected_report_count
      }
    end
  end
end
