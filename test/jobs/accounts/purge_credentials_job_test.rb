require "test_helper"

# 계정 연동 자격증명 purge 잡(account_linking_seasons_plan §Phase 5) — 창 경계·active 한정·멱등·
# 섹션별 digest nullify·나머지 snapshot 보존.
class Accounts::PurgeCredentialsJobTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "퍼지초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "퍼지생존자", password: "password")
    @seq = 90_000
  end

  def build_merge(created_at:, reversed_at: nil)
    @seq += 1
    AccountMerge.create!(
      surviving_user_id: @user.id, consumed_user_id: @seq,
      created_at: created_at, reversed_at: reversed_at,
      snapshot: {
        "old_pre_merge" => { "password_digest" => "OLDDIGEST", "name" => "옛이름", "classroom_id" => 7 },
        "new_attributes" => { "password_digest" => "NEWDIGEST", "name" => "새이름" },
        "manifest" => { "reports" => [ 1, 2 ] }
      }
    )
  end

  test "창 경과·미되돌림 병합의 두 섹션 digest 를 nullify 하고 나머지는 보존한다" do
    merge = build_merge(created_at: 20.days.ago)

    result = Accounts::PurgeCredentialsJob.new.perform

    assert_equal 1, result[:scanned]
    assert_equal 1, result[:purged]
    snapshot = merge.reload.snapshot
    assert_nil snapshot["old_pre_merge"]["password_digest"]
    assert_nil snapshot["new_attributes"]["password_digest"]
    assert_equal "옛이름", snapshot["old_pre_merge"]["name"], "PII 아닌 나머지는 보존"
    assert_equal [ 1, 2 ], snapshot["manifest"]["reports"], "매니페스트 보존(reverse 구조 복원용)"
  end

  test "창 이내 병합은 digest 를 보존한다" do
    merge = build_merge(created_at: 3.days.ago)

    result = Accounts::PurgeCredentialsJob.new.perform

    assert_equal 0, result[:purged]
    assert_equal "OLDDIGEST", merge.reload.snapshot["old_pre_merge"]["password_digest"]
  end

  test "되돌린 병합은 대상에서 제외한다(active 만)" do
    merge = build_merge(created_at: 20.days.ago, reversed_at: 1.day.ago)

    result = Accounts::PurgeCredentialsJob.new.perform

    assert_equal 0, result[:scanned]
    assert_equal "OLDDIGEST", merge.reload.snapshot["old_pre_merge"]["password_digest"]
  end

  test "멱등: 재실행하면 이미 purge 된 행은 다시 쓰지 않는다" do
    build_merge(created_at: 20.days.ago)

    Accounts::PurgeCredentialsJob.new.perform
    result = Accounts::PurgeCredentialsJob.new.perform

    assert_equal 1, result[:scanned]
    assert_equal 0, result[:purged], "digest 이미 nil → 변경 없음"
  end

  test "now: 주입으로 창 경계를 제어한다" do
    merge = build_merge(created_at: Time.current)

    result = Accounts::PurgeCredentialsJob.new.perform(now: 20.days.from_now)

    assert_equal 1, result[:purged]
    assert_nil merge.reload.snapshot["new_attributes"]["password_digest"]
  end
end
