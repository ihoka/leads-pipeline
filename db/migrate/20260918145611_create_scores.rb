class CreateScores < ActiveRecord::Migration[8.1]
  def change
    create_table :scores do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :icp_definition, null: false, foreign_key: true
      t.integer :total, null: false
      t.jsonb :dimensions, null: false, default: {}
      t.text :rationale
      t.bigint :cited_evidence_ids, array: true, null: false, default: []
      t.float :confidence
      t.string :model, null: false
      t.text :flagged_reason
      t.timestamps
    end
    add_index :scores, [ :lead_id, :created_at ]
  end
end
