class Lead < ApplicationRecord
  STATUSES = %w[new reviewing qualified disqualified nurture].freeze

  belongs_to :workspace
  belongs_to :company
  belongs_to :person, optional: true
  has_many :lead_discoveries, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
end
