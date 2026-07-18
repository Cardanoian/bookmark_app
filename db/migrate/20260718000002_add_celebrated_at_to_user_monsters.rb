class AddCelebratedAtToUserMonsters < ActiveRecord::Migration[8.1]
  # 발견 연출(축하 모달) 영속 드레인용. null = 아직 연출 안 함(미확인 발견).
  # 학생 페이지 로드 시 celebrated_at IS NULL 을 조회해 모달 큐에 넣고, 연출 후 마킹한다.
  # 셀프/교사 트리거 무관하게 유실 없이 전달(broadcast ephemeral 문제 회피).
  def up
    add_column :user_monsters, :celebrated_at, :datetime
    add_index :user_monsters, :user_id,
              where: "celebrated_at IS NULL",
              name: "index_user_monsters_pending_discovery"
    # 기존 보유 몬스터는 학생이 이미 알고 있으므로 연출 대상에서 제외(즉시 확인 처리).
    # 이 마이그레이션 이후 새로 발견되는 몬스터만 celebrated_at NULL 로 드레인된다.
    execute "UPDATE user_monsters SET celebrated_at = CURRENT_TIMESTAMP WHERE celebrated_at IS NULL"
  end

  def down
    remove_index :user_monsters, name: "index_user_monsters_pending_discovery"
    remove_column :user_monsters, :celebrated_at
  end
end
