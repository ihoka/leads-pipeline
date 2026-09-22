class Evidence < ApplicationRecord
  belongs_to :workspace
  belongs_to :subject, polymorphic: true
  belongs_to :raw_hit, optional: true

  validates :attribute_name, presence: true
  validates :source_key, presence: true
  validates :fetched_at, presence: true
end
