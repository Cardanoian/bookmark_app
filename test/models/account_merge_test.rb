require "test_helper"

# 계정 연동 감사 원장 모델(account_linking_seasons_plan §Phase 2) — 연관·active 스코프.
class AccountMergeTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "원장초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @survivor = User.create!(school: @school, classroom: @classroom, name: "생존자", password: "password")
    @performer = User.create!(school: @school, classroom: @classroom, name: "수행교사",
                              role: :teacher, password: "password", email: "perf@example.com")
  end

  test "surviving_user 와 performed_by 연관을 노출한다" do
    merge = AccountMerge.create!(
      surviving_user_id: @survivor.id,
      consumed_user_id: 9_999, # 삭제된 placeholder 의 역사적 원 id(실 user 없음)
      performed_by_id: @performer.id,
      performed_by_role: User.roles[@performer.role]
    )

    assert_equal @survivor, merge.surviving_user
    assert_equal @performer, merge.performed_by
  end

  test "consumed_user_id 는 실 user 가 없어도 보존된다(FK 없음)" do
    merge = AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 123_456)

    assert_equal 123_456, merge.reload.consumed_user_id
    assert_nil User.find_by(id: 123_456)
  end

  test "active 스코프는 미되돌림(reversed_at IS NULL) 원장만 반환한다" do
    open_merge = AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 1)
    reversed = AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 2,
                                    reversed_at: Time.current, reversed_by_id: @performer.id)

    assert_includes AccountMerge.active, open_merge
    assert_not_includes AccountMerge.active, reversed
  end

  test "활성 병합에서 같은 consumed_user_id 는 1회만 소비된다(부분 유니크)" do
    AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 777)

    dup = AccountMerge.new(surviving_user_id: @survivor.id, consumed_user_id: 777)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end

  test "되돌린 병합은 같은 consumed_user_id 를 다시 소비할 수 있다(부분 유니크는 활성만)" do
    AccountMerge.create!(surviving_user_id: @survivor.id, consumed_user_id: 888,
                         reversed_at: Time.current, reversed_by_id: @performer.id)

    again = AccountMerge.new(surviving_user_id: @survivor.id, consumed_user_id: 888)
    assert again.save, "되돌림 이후에는 같은 placeholder id 로 활성 원장을 만들 수 있어야 한다"
  end
end
