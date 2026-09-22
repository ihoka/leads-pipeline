class CreateCostLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :cost_ledger_entries do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: true
      t.string :kind, null: false
      t.string :model, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cached_input_tokens, null: false, default: 0
      t.timestamps
    end
    add_index :cost_ledger_entries, [ :workspace_id, :kind, :created_at ]
  end
end
