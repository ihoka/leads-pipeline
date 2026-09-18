# Verbatim source payload. Immutable by design: raw hits are the replay buffer
# that lets improved normalisation re-derive canonical records without
# re-fetching, which for paid sources costs money again.
class RawHit < ApplicationRecord
  belongs_to :workspace
  belongs_to :run_source_execution
  has_many :evidences, dependent: :nullify

  validates :source_key, :source_uid, :fetched_at, presence: true

  after_initialize { readonly! if persisted? }
  after_create { readonly! }
end
