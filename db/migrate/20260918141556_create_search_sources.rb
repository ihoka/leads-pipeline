class CreateSearchSources < ActiveRecord::Migration[8.1]
  def change
    create_table :search_sources do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :search, null: false, foreign_key: true
      t.string :adapter_key, null: false
      t.jsonb :adapter_params, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :search_sources, [ :search_id, :adapter_key ], unique: true
  end
end
