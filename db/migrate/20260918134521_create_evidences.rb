class CreateEvidences < ActiveRecord::Migration[8.1]
  def change
    create_table :evidences do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :subject, null: false, polymorphic: true
      t.bigint :raw_hit_id
      t.string :attribute_name, null: false
      t.text :value
      t.string :source_key, null: false
      t.string :source_url
      t.datetime :fetched_at, null: false
      t.float :confidence
      t.timestamps
    end
    add_index :evidences, [ :subject_type, :subject_id, :attribute_name ],
              name: "index_evidences_on_subject_and_attribute"
    add_index :evidences, :raw_hit_id
  end
end
