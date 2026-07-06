class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.string :title
      t.string :author
      t.string :publisher
      t.string :isbn
      t.string :cover_url
      t.string :grade_band
      t.integer :category, default: 0, null: false
      t.text :summary

      t.timestamps
    end

    add_index :books, :title
    add_index :books, :isbn
  end
end
