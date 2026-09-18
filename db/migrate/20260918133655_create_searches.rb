class CreateSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :searches do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.string :schedule
      t.timestamps
    end
    add_index :searches, [ :workspace_id, :status ]
  end
end
