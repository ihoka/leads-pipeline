class CreateSuppressions < ActiveRecord::Migration[8.1]
  def change
    create_table :suppressions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :domain
      t.string :email
      t.string :reason, null: false
      t.text :note
      t.timestamps
    end
    add_index :suppressions, [ :workspace_id, :domain ]
  end
end
