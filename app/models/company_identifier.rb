class CompanyIdentifier < ApplicationRecord
  KINDS = %w[domain linkedin_slug crunchbase_id normalized_name].freeze

  belongs_to :workspace
  belongs_to :company

  validates :kind, inclusion: { in: KINDS }
  validates :value, presence: true
  validates :value, uniqueness: { scope: [ :workspace_id, :kind ] }
end
