# 몬스터 라인 1단계 폼의 자동 해금 조건(docs/monster_unlocks.md §5). 라인 단위 규칙을
# stage 1 폼 행에 얹는다(evolve_condition 과 같은 조건 해시 문법·화이트리스트, 별도 컬럼으로 분리).
# nullable — stage 2·3 폼과 아직 해금 규칙이 없는 라인은 NULL 로 남는다.
class AddUnlockConditionToMonsterSpecies < ActiveRecord::Migration[8.1]
  def change
    add_column :monster_species, :unlock_condition, :json
  end
end
