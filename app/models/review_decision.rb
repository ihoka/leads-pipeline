# The operator's verdict, and the training signal for ICP refinement.
#
# The reason code is mandatory because free text does not aggregate: "you
# disqualified twelve of fourteen companies under twenty staff" is only
# computable from a controlled vocabulary.
class ReviewDecision < ApplicationRecord
  DECISIONS = %w[advance disqualify snooze].freeze
  REASON_CODES = %w[
    too_small too_large wrong_stack no_budget_signal
    already_client no_contact_route not_now other
  ].freeze
  DEFAULT_SNOOZE_DAYS = 90

  belongs_to :workspace
  belongs_to :lead

  validates :decision, inclusion: { in: DECISIONS }
  validates :reason_code, inclusion: { in: REASON_CODES }

  def self.record!(lead:, decision:, reason_code:, note: nil, snooze_days: DEFAULT_SNOOZE_DAYS)
    transaction do
      entry = create!(
        workspace: lead.workspace, lead: lead, decision: decision,
        reason_code: reason_code, note: note, decided_at: Time.current
      )
      apply_to_lead(lead, decision, snooze_days)
      entry
    end
  end

  def self.apply_to_lead(lead, decision, snooze_days)
    case decision
    when "advance"    then lead.update!(status: "qualified")
    when "disqualify" then lead.update!(status: "disqualified")
    when "snooze"     then lead.update!(snoozed_until: snooze_days.to_i.days.from_now)
    end
  end
end
