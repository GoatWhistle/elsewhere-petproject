class CreatePhaseZeroStore < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto"
    enable_extension "postgis"

    create_table :planning_sessions, id: :uuid do |t|
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    create_table :future_versions, id: :uuid do |t|
      t.uuid :session_id, null: false
      t.uuid :lineage_id, null: false
      t.uuid :parent_id
      t.integer :version, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :future_versions, :session_id
    add_index :future_versions, [:lineage_id, :version], unique: true

    create_table :jobs, id: :uuid do |t|
      t.string :kind, null: false
      t.string :status, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :jobs, :status
  end
end
