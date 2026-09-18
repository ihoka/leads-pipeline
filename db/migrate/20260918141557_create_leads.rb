class CreateLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :leads do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :person, foreign_key: true
      t.string :status, null: false, default: "new"
      t.datetime :snoozed_until
      t.timestamps
    end
    add_index :leads, [ :workspace_id, :company_id ], unique: true
  end
end
