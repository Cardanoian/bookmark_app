# monster_species.evolves_from_id → monster_species(자기참조) FK 에 on_delete: :nullify 를 준다(#8).
# 기존 FK 는 on_delete 미지정(=RESTRICT)이라, 진화 이전 폼을 직접 SQL 로 삭제하면 다음 폼이
# 참조 중일 때 삭제가 막힌다. 모델은 이미 `has_many :next_forms, dependent: :nullify` 로 부모 삭제 시
# 자식의 evolves_from_id 를 끊으므로, DB FK 도 nullify 로 맞춰 raw delete 경로까지 정합화한다.
# evolves_from_id 는 nullable(optional belongs_to)이라 nullify 가 안전하다.
#
# SQLite 는 FK 변경을 테이블 재빌드로 처리한다. up/down 모두 재빌드·데이터 복사 → 왕복 무손실.
class AddOnDeleteToMonsterSpeciesSelfFk < ActiveRecord::Migration[8.1]
  def up
    if foreign_key_exists?(:monster_species, :monster_species, column: :evolves_from_id)
      remove_foreign_key :monster_species, column: :evolves_from_id
    end
    add_foreign_key :monster_species, :monster_species, column: :evolves_from_id, on_delete: :nullify
  end

  def down
    if foreign_key_exists?(:monster_species, :monster_species, column: :evolves_from_id)
      remove_foreign_key :monster_species, column: :evolves_from_id
    end
    add_foreign_key :monster_species, :monster_species, column: :evolves_from_id
  end
end
