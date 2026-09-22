class CreateLeadDiscoveries < ActiveRecord::Migration[8.1]
  def change
    create_table :lead_discoveries do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :run, null: false, foreign_key: true
      t.references :search, null: false, foreign_key: true
      t.datetime :discovered_at, null: false
      t.timestamps
    end
  end
end
