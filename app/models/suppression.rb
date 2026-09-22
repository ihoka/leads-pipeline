# Checked before anything reaches the review queue. Current clients,
# competitors, and anyone who has opted out must never be surfaced, and under
# GDPR the opt-out check is a requirement rather than a courtesy.
class Suppression < ApplicationRecord
  REASONS = %w[current_client competitor opted_out do_not_contact].freeze

  belongs_to :workspace

  validates :reason, inclusion: { in: REASONS }
  validate :domain_or_email_present

  # Domain-only suppression check. Email-based suppressions are not enforced by this
  # method and should not be relied on: person/email data is not ingested until
  # Milestone 3, so an email-only opt-out cannot be matched against incoming leads yet.
  def self.suppressed?(workspace:, domain:)
    return false if domain.blank?

    where(workspace: workspace).where("lower(domain) = ?", domain.downcase).exists?
  end

  private
    def domain_or_email_present
      errors.add(:base, "domain or email required") if domain.blank? && email.blank?
    end
end
