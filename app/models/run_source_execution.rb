class RunSourceExecution < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :workspace
  belongs_to :run
  has_many :raw_hits, dependent: :restrict_with_exception

  validates :source_key, presence: true
  validates :status, inclusion: { in: STATUSES }
end
