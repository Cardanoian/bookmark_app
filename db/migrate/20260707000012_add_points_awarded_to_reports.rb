# 독후감이 이미 지급한 포인트를 기록한다. 재첨삭(본문 수정 후 재제출) 시
# 전체를 재지급하지 않고 차액만 반영하기 위한 멱등성 컬럼.
class AddPointsAwardedToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :points_awarded, :integer, default: 0, null: false
  end
end
