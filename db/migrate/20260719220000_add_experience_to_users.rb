class AddExperienceToUsers < ActiveRecord::Migration[8.0]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"

    has_many :migration_user_monsters,
             class_name: "AddExperienceToUsers::MigrationUserMonster",
             foreign_key: :user_id
  end

  class MigrationUserMonster < ActiveRecord::Base
    self.table_name = "user_monsters"

    belongs_to :migration_monster_species,
               class_name: "AddExperienceToUsers::MigrationMonsterSpecies",
               foreign_key: :monster_species_id
  end

  class MigrationMonsterSpecies < ActiveRecord::Base
    self.table_name = "monster_species"

    belongs_to :previous_form,
               class_name: "AddExperienceToUsers::MigrationMonsterSpecies",
               foreign_key: :evolves_from_id,
               optional: true
  end

  def up
    add_column :users, :experience, :integer, default: 0, null: false

    MigrationUser.reset_column_information
    MigrationUserMonster.reset_column_information
    MigrationMonsterSpecies.reset_column_information

    # 과거에는 포인트 잔액이 곧 레벨 기준이어서 소비 이력을 따로 남기지 않았다. 현재 폼까지
    # 진화하며 반드시 지불한 각 이전 폼의 비용은 카탈로그 체인에서 확정적으로 복원할 수 있다.
    # 따라서 기존 경험치는 `현재 잔액 + 확인 가능한 진화 비용`으로 잡아 소비 때문에 내려간
    # 레벨을 되살린다. 삭제된 옛 상점 등 원장이 없는 소비는 추측해 부풀리지 않는다.
    MigrationUser.includes(migration_user_monsters: :migration_monster_species).find_each do |user|
      spent_on_evolution = user.migration_user_monsters.sum do |user_monster|
        evolution_cost_paid_before(user_monster.migration_monster_species)
      end

      user.update_columns(experience: user.points.to_i + spent_on_evolution)
    end
  end

  def down
    remove_column :users, :experience
  end

  private

  def evolution_cost_paid_before(current_species)
    cost = 0
    species = current_species&.previous_form

    while species
      cost += species.evolve_condition.to_h.fetch("points", 0).to_i
      species = species.previous_form
    end

    cost
  end
end
