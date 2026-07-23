class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :actor_role, null: false
      t.string :action, null: false
      t.string :target_type
      t.integer :target_id
      t.integer :school_id
      t.integer :classroom_id
      t.json :metadata, null: false, default: {}
      t.string :ip_address
      t.string :user_agent
      t.datetime :created_at, null: false
    end

    add_index :audit_logs, [ :action, :created_at ]
    add_index :audit_logs, [ :actor_id, :created_at ]
    add_index :audit_logs, [ :target_type, :target_id ]
    add_index :audit_logs, [ :school_id, :created_at ]
  end
end
