# 상점 스키마 드롭(menu_refactor 심화 PR8, 파괴적 DDL·후행). PR7 에서 상점 런타임 코드(모델·컨트롤러·
# 뷰·정책·먹이)를 모두 제거했고, 이제 테이블과 미사용 컬럼을 드롭한다. 2단계 배포의 마지막 단계:
# 구버전(상점 코드) 인스턴스가 모두 내려간 뒤 적용해야 안전하다(운영 롤링 배포 시).
#   드롭 순서: purchases(shop_items·users FK 보유) → shop_items → user_monsters.care.
# care 는 PR7 에서 먹이주기(monsters#feed) 제거로 read/write 가 0 이 된 미사용 컬럼이다(§2.C.2).
# down 은 스키마 왕복을 위해 테이블·컬럼을 재생성하나 데이터는 복구하지 않는다(상점 제거는 비가역 정책).
class DropShopSchema < ActiveRecord::Migration[8.1]
  def up
    drop_table :purchases
    drop_table :shop_items
    remove_column :user_monsters, :care
  end

  def down
    create_table :shop_items do |t|
      t.integer :category, default: 0
      t.boolean :consumable, default: false, null: false
      t.integer :cost, default: 0
      t.json :effect
      t.string :icon
      t.string :image_key
      t.string :name
      t.timestamps
    end

    create_table :purchases do |t|
      t.datetime :bought_at
      t.integer :quantity, default: 1, null: false
      t.references :shop_item, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :purchases, [ :user_id, :shop_item_id ], unique: true

    add_column :user_monsters, :care, :json
  end
end
