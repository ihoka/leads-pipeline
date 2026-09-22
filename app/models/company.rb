class Company < ApplicationRecord
  belongs_to :workspace
  has_many :company_identifiers, dependent: :destroy
  has_many :people, dependent: :nullify
  has_many :evidences, as: :subject, dependent: :destroy

  before_create { self.first_seen_at ||= Time.current }
end
