# 랭킹 시즌제 점수 테이블(account_linking_seasons_plan §Phase 0). 시즌 = academic_year(연 1회,
# Classroom.current_academic_year 단일 진실). 평생 카운터(users.experience/points·레벨·명예의전당)는
# 불변으로 두고, 랭킹만 이 테이블의 experience_earned 로 분리해 매 학년도 0에서 재출발시킨다.
# Pointable 의 3 초크포인트(award_points·credit_points!·revoke_points!)가 raw SQLite upsert 로
# academic_year 별 행을 원자 증감한다(ON CONFLICT(academic_year, user_id) DO UPDATE).
class CreateSeasonScores < ActiveRecord::Migration[8.1]
  def change
    create_table :season_scores do |t|
      t.integer :academic_year, null: false
      # user_id → users on_delete: :cascade. 유일 신원 인덱스가 (academic_year, user_id) 라
      # 자동 user_id 인덱스는 만들지 않는다(index: false) — 인덱스는 딱 1개만 둔다.
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :experience_earned, null: false, default: 0
      t.integer :points_earned, null: false, default: 0
      # 스냅샷 3컬럼(school_id/classroom_id/grade): 감사·과거 시즌 재현 전용 —
      # 랭킹 그룹핑 키가 아니다(RankingBoard 는 현재 소속 users.classroom_id/school_id 로 group).
      # 최초 INSERT 때만 채우고 이후 증분 UPDATE(ON CONFLICT) 에서는 건드리지 않는다.
      t.integer :school_id
      t.integer :classroom_id
      t.integer :grade
      t.timestamps
    end

    # 인덱스는 (academic_year, user_id) UNIQUE 단 1개.
    # Pointable 의 ON CONFLICT(academic_year, user_id) upsert 대상이자,
    # RankingBoard 의 현재 학년도 LEFT JOIN(user_id + academic_year 상수) 조회 인덱스.
    # 죽은 인덱스([academic_year,classroom_id]·[…,school_id]·[…,grade])는 넣지 않는다.
    add_index :season_scores, [ :academic_year, :user_id ], unique: true, name: "index_season_scores_identity"
  end
end
