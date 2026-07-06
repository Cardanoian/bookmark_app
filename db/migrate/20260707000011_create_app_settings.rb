# 시스템 설정(P7.4). 총괄관리자가 관리하는 전역 키·값(기능 플래그·기본 루브릭 가중치·
# 시즌 배너 등). value 는 JSON. API 키는 절대 저장하지 않는다(모델 가드).
class CreateAppSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :app_settings do |t|
      t.string :key, null: false
      t.json :value
      t.string :description

      t.timestamps
    end

    add_index :app_settings, :key, unique: true
  end
end
