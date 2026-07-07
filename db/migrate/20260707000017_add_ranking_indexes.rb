# 랭킹 그룹 집계(P3.1)를 지지하는 복합 인덱스(P3.5). 3.1 적용 후 추가.
# nation_ranking:  WHERE role GROUP BY school_id, SUM(points)    → (school_id, role, points)
# school_ranking:  WHERE role AND classroom_id IN(..) GROUP BY classroom_id, SUM/COUNT(points)
#                                                                 → (classroom_id, role, points)
# 두 인덱스 모두 그룹핑 컬럼을 선두에 두어 정렬 없는 그룹핑을 돕고, 필터(role)·집계(points)를
# 포함해 커버링 인덱스로 동작한다. 재실행 안전(if_not_exists) — 게이트는 lead 가 db:migrate 로 수행.
class AddRankingIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :users, [ :school_id, :role, :points ],
              name: "index_users_on_school_role_points", if_not_exists: true
    add_index :users, [ :classroom_id, :role, :points ],
              name: "index_users_on_classroom_role_points", if_not_exists: true
  end
end
