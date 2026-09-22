class AddRawHitFkToEvidences < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :evidences, :raw_hits
  end
end
