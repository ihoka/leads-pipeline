class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :company, foreign_key: true
      t.string :name
      t.string :title
      t.string :email
      t.string :linkedin_url
      t.string :seniority
      t.timestamps
    end
  end
end
