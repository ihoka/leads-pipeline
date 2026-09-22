class Run < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :workspace
  belongs_to :search
  belongs_to :icp_definition
  has_many :run_source_executions, dependent: :destroy
  has_many :raw_hits, through: :run_source_executions

  validates :status, inclusion: { in: STATUSES }

  # Increments a counter inside the stats jsonb. Uses a row lock because
  # source executions run concurrently and would otherwise clobber each other.
  def record_stats!(key, amount)
    with_lock do
      stats[key.to_s] = stats.fetch(key.to_s, 0) + amount
      save!
    end
  end
end
