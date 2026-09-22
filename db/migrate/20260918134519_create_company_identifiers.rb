class CreateCompanyIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :company_identifiers do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :value, null: false
      t.timestamps
    end
    add_index :company_identifiers, [ :workspace_id, :kind, :value ], unique: true,
              name: "index_company_identifiers_uniqueness"
  end
end
