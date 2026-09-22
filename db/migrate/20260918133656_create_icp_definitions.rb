class CreateIcpDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :icp_definitions do |t|
      t.references :search, null: false, foreign_key: true
      t.integer :version, null: false
      t.text :brief, null: false
      t.jsonb :compiled_criteria, null: false, default: {}
      t.jsonb :scoring_rubric, null: false, default: {}
      t.timestamps
    end
    add_index :icp_definitions, [ :search_id, :version ], unique: true
  end
end
