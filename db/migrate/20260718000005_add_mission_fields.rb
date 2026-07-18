# 학급 미션 재설계(menu_refactor 심화 §2.A.5) additive 스키마 — missions 컬럼 보강.
# 기존 컬럼(book_id·classroom_id·title·start_date·end_date)은 그대로 두고(드롭 금지),
# 발행 생명주기(status·published_at·cancelled_at)·작성자(created_by)·보상(reward_points)·
# 설명(description)만 추가한다. book_id 는 PR6(참여방식 제거)에서 별도로 드롭한다.
class AddMissionFields < ActiveRecord::Migration[8.1]
  def change
    # 작성자(교사). 사용자 삭제 시 미션은 남기고 참조만 끊는다(on_delete: nullify).
    add_reference :missions, :created_by, null: true, index: true,
                  foreign_key: { to_table: :users, on_delete: :nullify }

    add_column :missions, :description,   :text
    add_column :missions, :reward_points, :integer,  null: false, default: 0
    add_column :missions, :status,        :integer,  null: false, default: 0
    add_column :missions, :published_at,  :datetime
    add_column :missions, :cancelled_at,  :datetime

    # 학급별 상태·기간 조회(교사 미션 목록·활성 미션 카드).
    add_index :missions, [ :classroom_id, :status, :start_date ]
  end
end
