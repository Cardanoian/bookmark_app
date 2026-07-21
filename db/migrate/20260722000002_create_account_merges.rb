# 계정 연동(MERGE) 감사 원장(account_linking_seasons_plan §Phase 2). 학년이 바뀌어 새 담임이
# 만든 placeholder 계정(consumed)을 접어 삭제하고, 기록이 있는 작년 계정(surviving)을 생존자로
# 남기는 병합의 **원장**이다. 매 병합은 이동행 매니페스트 + pre-merge 스냅샷을 snapshot(JSON)에
# 남겨 14일 시간창 되돌리기(reverse!, Phase 4)가 실질적으로 가역이 되게 한다.
#
# consumed_user_id 는 삭제될 placeholder 의 **역사적 원 id** 다 — FK 없이 감사 사실로만 보존한다
# (그 user 행은 병합 중 raw delete 되므로 참조 무결성을 걸 수 없다). surviving/performed/reversed_by
# 는 실재 users 를 가리키므로 FK on_delete: :nullify 를 건다.
class CreateAccountMerges < ActiveRecord::Migration[8.1]
  def change
    create_table :account_merges do |t|
      # 생존자(작년 계정). 병합 후에도 살아남는 실 계정 — NOT NULL. FK nullify 는 계정 하드삭제라는
      # 예상 밖 경로에서만 의미가 있고(NOT NULL 이라 실제로는 삭제를 사실상 차단), 감사 원장이
      # 소리 없이 surviving 링크를 잃지 않게 한다(계획 §Phase 2 지정).
      t.integer :surviving_user_id, null: false
      # 소비된 placeholder 의 원 id(FK 없음 — 역사적 사실 보존).
      t.integer :consumed_user_id
      # 병합을 수행한 주체(학생 셀프서브/교사/총괄) 와 그 역할 정수 스냅샷.
      t.integer :performed_by_id
      t.integer :performed_by_role
      # 병합 전/후 소속(감사·통계·되돌리기 참조).
      t.integer :from_classroom_id
      t.integer :to_classroom_id
      t.integer :from_school_id
      t.integer :to_school_id
      # 이동 카운트 요약(뷰/감사) 과 이동행 매니페스트 + pre-merge 스냅샷(되돌리기 근거).
      t.json :moved_counts
      t.json :snapshot
      # 되돌리기 스탬프(Phase 4 reverse! 가 채운다).
      t.datetime :reversed_at
      t.integer :reversed_by_id
      t.timestamps
    end

    add_index :account_merges, :surviving_user_id
    add_index :account_merges, :consumed_user_id
    add_index :account_merges, :reversed_at
    # 부분 유니크: 활성(미되돌림) 병합에서 한 placeholder 는 **1회만** 소비될 수 있다.
    # 동시 이중병합·재시도가 같은 consumed_user_id 로 두 번째 활성 원장을 만들면 RecordNotUnique
    # 로 fail-closed 롤백된다(조건부 claim 과 짝을 이루는 idempotency 백스톱).
    add_index :account_merges, :consumed_user_id, unique: true,
              where: "reversed_at IS NULL", name: "index_account_merges_active_consumed"

    add_foreign_key :account_merges, :users, column: :surviving_user_id, on_delete: :nullify
    add_foreign_key :account_merges, :users, column: :performed_by_id, on_delete: :nullify
    add_foreign_key :account_merges, :users, column: :reversed_by_id, on_delete: :nullify
  end
end
