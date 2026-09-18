class Search < ApplicationRecord
  STATUSES = %w[draft active paused].freeze

  belongs_to :workspace
  has_many :icp_definitions, -> { order(version: :desc) }, dependent: :destroy
  has_many :runs, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def active_icp_definition
    icp_definitions.first
  end
end
