# Append-only. Re-scoring inserts a new row so that score drift is visible and
# two rubric versions can be diffed over the same lead set.
class Score < ApplicationRecord
  belongs_to :workspace
  belongs_to :lead
  belongs_to :icp_definition

  validates :total, presence: true, inclusion: { in: 0..100 }
  validates :model, presence: true

  after_initialize { readonly! if persisted? }
  after_create { readonly! }

  def flagged? = flagged_reason.present?
end
