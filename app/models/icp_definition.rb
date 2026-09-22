class IcpDefinition < ApplicationRecord
  belongs_to :search

  validates :brief, presence: true
  validates :version, presence: true, uniqueness: { scope: :search_id }

  before_validation :assign_version, on: :create

  private
    def assign_version
      self.version ||= (search.icp_definitions.maximum(:version) || 0) + 1
    end
end
