require "test_helper"

# 미션 보상 정확히-1회의 **병렬** 검증(menu_refactor 심화 §2.A.1 C1·§6.2). 두 스레드/두 커넥션이
# 같은 participation 을 동시에 지급해도 조건부 UPDATE(`WHERE rewarded_at IS NULL`) 선점으로 정확히
# 1회만 크레딧됨을 확인한다(순차 멱등 테스트로는 못 잡는 read-then-write 경쟁). 스레드가 서로의
# 커밋을 봐야 하므로 트랜잭션 픽스처를 끈다(fk_on_delete_roundtrip 선례).
class MissionRewardConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  REWARD = 60

  setup do
    @school = School.create!(name: "동시초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "동시생", password: "password", points: 0)
    @mission = Mission.new(classroom: @classroom, title: "동시미션", reward_points: REWARD,
                           start_date: Date.current - 1, end_date: Date.current + 5)
    @mission.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    @mission.status = :published
    @mission.save!
    Report.create!(user: @student, classroom: @classroom, book_title: "책", reviewed: true, created_at: Time.current)
    @participation = MissionParticipation.create!(mission: @mission, user: @student)
  end

  teardown do
    MissionParticipation.where(mission_id: Mission.where(classroom_id: @classroom&.id)).delete_all
    MissionGoal.where(mission_id: Mission.where(classroom_id: @classroom&.id)).delete_all
    Mission.where(classroom_id: @classroom&.id).delete_all
    Report.where(classroom_id: @classroom&.id).delete_all
    User.where(school_id: @school&.id).delete_all
    Classroom.where(school_id: @school&.id).delete_all
    School.where(id: @school&.id).delete_all
  end

  test "두 스레드가 동시에 지급해도 정확히 1회만 크레딧된다" do
    part_id = @participation.id
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Missions::Rewarder.new.reward!(MissionParticipation.find(part_id))
        rescue ActiveRecord::StatementInvalid
          # SQLite busy 경쟁 시 한 스레드가 실패할 수 있으나, 그래도 다른 스레드가 정확히 1회 지급.
          nil
        end
      end
    end
    threads.each(&:join)

    @participation.reload
    assert @participation.rewarded_at.present?
    assert_equal REWARD, @participation.reward_points_awarded
    assert_equal REWARD, @student.reload.points, "정확히 1회분만 적립돼야 한다(이중지급 없음)"
  end
end
