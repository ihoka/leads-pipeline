class Lead < ApplicationRecord
  STATUSES = %w[new reviewing qualified disqualified nurture].freeze

  belongs_to :workspace
  belongs_to :company
  belongs_to :person, optional: true
  has_many :lead_discoveries, dependent: :destroy
  has_many :scores, dependent: :delete_all
  has_many :review_decisions, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  def latest_score = scores.order(created_at: :desc, id: :desc).first
end
