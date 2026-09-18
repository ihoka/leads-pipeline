class CreateReviewDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :review_decisions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.string :decision, null: false
      t.string :reason_code, null: false
      t.text :note
      t.datetime :decided_at, null: false
      t.timestamps
    end
    add_index :review_decisions, [ :workspace_id, :reason_code ]
  end
end
