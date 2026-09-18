class CreateRawHits < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_hits do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :run_source_execution, null: false, foreign_key: true
      t.string :source_key, null: false
      t.string :source_uid, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :raw_hits, [ :workspace_id, :source_key, :source_uid ]
  end
end
