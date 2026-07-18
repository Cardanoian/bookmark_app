class AddSyncMetadataToSchools < ActiveRecord::Migration[8.1]
  def change
    add_column :schools, :active, :boolean, null: false, default: true
    add_column :schools, :data_source, :string, null: false, default: "manual"
    add_column :schools, :synced_at, :datetime

    add_index :schools, :data_source
    add_index :schools, [ :active, :region, :gu ], name: "index_schools_on_active_region_gu"
  end
end
