# 챌린지 참여 시점(joined_at) 기록. 진행 집계 창의 하한이 '챌린지 기간 시작'에서 '학생이 참여한
# 시점'으로 바뀌므로(참여 후 활동만 인정), participation 원장에 참여 시각을 남긴다.
#
# 기존 행 백필: 종전 표시·이미 지급된 보상과 어긋나지 않게 **챌린지 창 시작**(starts_on 00:00 KST,
# 없으면 챌린지 생성 시각)으로 채운다 → 기존 참여의 진행률은 마이그레이션 전후 불변이고, 새 규칙은
# 앞으로의 참여에만 적용된다. `datetime(starts_on, '-9 hours')` 는 KST 00:00 을 UTC 로 옮긴 값이다
# (Challenge#window_start + Challenges::ProgressCalculator 의 ZONE 경계와 동일 의미).
class AddJoinedAtToChallengeParticipations < ActiveRecord::Migration[8.1]
  def up
    add_column :challenge_participations, :joined_at, :datetime

    execute(<<~SQL.squish)
      UPDATE challenge_participations SET joined_at = COALESCE(
        (SELECT datetime(c.starts_on, '-9 hours') FROM challenges c
           WHERE c.id = challenge_participations.challenge_id AND c.starts_on IS NOT NULL),
        (SELECT c.created_at FROM challenges c WHERE c.id = challenge_participations.challenge_id),
        challenge_participations.created_at
      )
    SQL

    change_column_null :challenge_participations, :joined_at, false
  end

  def down
    remove_column :challenge_participations, :joined_at
  end
end
