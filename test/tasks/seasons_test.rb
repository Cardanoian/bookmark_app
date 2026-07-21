require "test_helper"
require "rake"

# seasons:reconcile 운영 rake 스모크(account_linking_seasons_plan §Phase 5). 빈/비어있지 않은 상태
# 모두 크래시 0, 읽기 전용(파괴 0).
class SeasonsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("seasons:reconcile")
    @school = School.create!(name: "시즌점검초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "시즌점검학생", password: "password")
  end

  def run_task(name)
    Rake::Task[name].reenable
    capture_io { Rake::Task[name].invoke }.first
  end

  test "seasons:reconcile 는 빈 데이터에서도 크래시 없이 점검 리포트를 낸다" do
    out = run_task("seasons:reconcile")

    assert_match "시즌 점검", out
    assert_match "유령 행", out
    assert_match "✓", out
  end

  test "seasons:reconcile 는 현재 학년도 합과 무결성을 집계한다" do
    year = Classroom.current_academic_year
    SeasonScore.create!(user: @user, academic_year: year, experience_earned: 40, points_earned: 10)

    out = run_task("seasons:reconcile")

    assert_match "현재 학년도 행: 1", out
    assert_match "experience_earned 합: 40", out
    assert_match "유령 행(존재 안 하는 user_id): 0 ✓", out
  end
end
