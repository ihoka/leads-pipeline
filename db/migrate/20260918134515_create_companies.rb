class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name
      t.string :domain
      t.string :location
      t.string :industry
      t.integer :size_estimate
      t.datetime :first_seen_at
      t.timestamps
    end
  end
end
