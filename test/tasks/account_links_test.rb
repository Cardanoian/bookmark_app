require "test_helper"
require "rake"

# account_links:audit / account_links:purge_credentials 운영 rake 스모크(account_linking_seasons_plan §Phase 5).
# 빈/비어있지 않은 상태 모두 크래시 0, snapshot PII 미노출.
class AccountLinksTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("account_links:audit")
    @school = School.create!(name: "감사초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "감사생존자", password: "password")
  end

  def run_task(name)
    Rake::Task[name].reenable
    capture_io { Rake::Task[name].invoke }.first
  end

  test "account_links:audit 는 빈 데이터에서도 크래시 없이 요약·FK 리포트를 낸다" do
    out = run_task("account_links:audit")

    assert_match "계정 연동 감사", out
    assert_match "총 병합: 0", out
    assert_match "위반 없음", out
  end

  test "account_links:audit 는 병합 요약을 출력하되 snapshot PII 는 출력하지 않는다" do
    AccountMerge.create!(surviving_user_id: @user.id, consumed_user_id: 12_345,
                         moved_counts: { "reports" => 3, "monsters" => 2 },
                         snapshot: { "old_pre_merge" => { "password_digest" => "SECRETDIGEST" } })

    out = run_task("account_links:audit")

    assert_match "총 병합: 1", out
    assert_match "reports=3", out
    assert_not_includes out, "SECRETDIGEST", "snapshot PII 는 감사 출력에 노출되지 않는다"
  end

  test "account_links:purge_credentials 는 빈 데이터에서도 크래시 없이 리포트를 낸다" do
    out = run_task("account_links:purge_credentials")

    assert_match "자격증명 purge", out
    assert_match "digest purge: 0건", out
  end

  test "account_links:purge_credentials 는 창 경과 병합 digest 를 purge 한다" do
    merge = AccountMerge.create!(surviving_user_id: @user.id, consumed_user_id: 22_222, created_at: 20.days.ago,
                                 snapshot: { "old_pre_merge" => { "password_digest" => "OLDD" },
                                             "new_attributes" => { "password_digest" => "NEWD" } })

    out = run_task("account_links:purge_credentials")

    assert_match "digest purge: 1건", out
    assert_nil merge.reload.snapshot["old_pre_merge"]["password_digest"]
  end
end
