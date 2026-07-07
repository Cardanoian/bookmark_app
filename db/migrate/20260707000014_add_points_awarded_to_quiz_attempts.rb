# 퀴즈 재플레이 파밍 차단(§1.2). 이 판이 지급한 적립액을 기록해, 재플레이 시
# 전체를 재지급하지 않고 이 학생의 최고점 초과분(delta)만 반영하기 위한 멱등성 컬럼.
# (독후감 재첨삭의 reports.points_awarded 델타 패턴을 재사용.)
class AddPointsAwardedToQuizAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :quiz_attempts, :points_awarded, :integer, default: 0, null: false
  end
end
