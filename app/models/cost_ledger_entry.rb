# Every model call is recorded so that an always-on system's spend is visible
# before the invoice. Prices are estimates for local visibility, not billing
# truth.
class CostLedgerEntry < ApplicationRecord
  INPUT_CENTS_PER_MTOK = 500
  OUTPUT_CENTS_PER_MTOK = 2_500
  CACHE_READ_DISCOUNT = 0.1

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true

  def self.record!(workspace:, kind:, model:, usage:, subject: nil)
    create!(
      workspace: workspace, kind: kind, model: model, subject: subject,
      input_tokens: read_usage(usage, :input_tokens),
      output_tokens: read_usage(usage, :output_tokens),
      cached_input_tokens: read_usage(usage, :cache_read_input_tokens)
    )
  end

  def self.read_usage(usage, field)
    usage.respond_to?(field) ? usage.public_send(field).to_i : 0
  end

  def estimated_cost_cents
    input = input_tokens * INPUT_CENTS_PER_MTOK
    output = output_tokens * OUTPUT_CENTS_PER_MTOK
    cached = cached_input_tokens * INPUT_CENTS_PER_MTOK * CACHE_READ_DISCOUNT

    ((input + output + cached) / 1_000_000.0).round
  end
end
