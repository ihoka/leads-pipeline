class CreateRunSourceExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :run_source_executions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :run, null: false, foreign_key: true
      t.string :source_key, null: false
      t.string :status, null: false, default: "pending"
      t.integer :hits_count, null: false, default: 0
      t.integer :cost_cents, null: false, default: 0
      t.text :error_message
      t.timestamps
    end
  end
end
