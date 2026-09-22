class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :search, null: false, foreign_key: true
      t.references :icp_definition, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.jsonb :stats, null: false, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end
