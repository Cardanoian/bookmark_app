module Missions
  # 학생 미션 자동 배정(menu_refactor 심화 §2.A.6·§8.6). 참여 버튼 없이 서버가 배정한다.
  #   on_publish(mission) — 발행 시 학급 학생 전원 배정 + 각자 즉시 평가.
  #   for_user(user)      — 학생 학급 편입/변경 시 현재 학급의 진행 중 published 미션에 배정 + 즉시 평가.
  # 배정 직후 즉시 EvaluateProgress 를 태워 "편입 前 창 내 활동"(지연배정 갭)을 메운다. 신규 생성 행이
  # 없으면 no-op(멱등). MonsterUnlock self-heal 은 completed_at 을 재생성하지 못하므로 안전망이 아니며,
  # 안전망은 이 즉시 평가 + Missions::ReevaluateJob(주기 백스톱)다.
  class AssignmentSync
    def self.on_publish(mission)
      now = Time.current
      students = mission.classroom.users.merge(User.student).to_a
      students.each { |student| assign(mission, student, now) }
      # 즉시 평가(발행 시점 이전 창 내 활동·기존 활동 반영).
      students.each { |student| EvaluateProgress.new(student).evaluate_pending }
    end

    def self.for_user(user)
      return unless user.student? && user.classroom_id

      now = Time.current
      Mission.published
             .where(classroom_id: user.classroom_id)
             .where("start_date <= :d AND end_date >= :d", d: Date.current)
             .find_each { |mission| assign(mission, user, now) }
      EvaluateProgress.new(user).evaluate_pending
    end

    # 배정 1행(멱등). 순차 중복은 모델 uniqueness 검증이 걸러(create 비-bang → 미저장 반환, 무해),
    # 동시 경쟁만 DB 유니크 인덱스가 RecordNotUnique 로 잡는다(book_intro vote 와 동일 관용구).
    # 이미 배정된 학생의 assigned_at 은 보존한다.
    def self.assign(mission, user, now)
      MissionParticipation.create(mission_id: mission.id, user_id: user.id, assigned_at: now)
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
