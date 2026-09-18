require "test_helper"

class CostLedgerEntryTest < ActiveSupport::TestCase
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, keyword_init: true)

  setup { @workspace = Workspace.create!(name: "Personal") }

  test "records token counts from a usage object" do
    entry = CostLedgerEntry.record!(
      workspace: @workspace, kind: "scoring", model: "claude-opus-5",
      usage: Usage.new(input_tokens: 1_000, output_tokens: 500, cache_read_input_tokens: 4_000)
    )

    assert_equal 1_000, entry.input_tokens
    assert_equal 500, entry.output_tokens
    assert_equal 4_000, entry.cached_input_tokens
  end

  test "estimates cost in cents" do
    entry = CostLedgerEntry.record!(
      workspace: @workspace, kind: "scoring", model: "claude-opus-5",
      usage: Usage.new(input_tokens: 1_000_000, output_tokens: 0, cache_read_input_tokens: 0)
    )

    assert_equal 500, entry.estimated_cost_cents
  end

  test "prices cached reads at a tenth of the input rate" do
    entry = CostLedgerEntry.record!(
      workspace: @workspace, kind: "scoring", model: "claude-opus-5",
      usage: Usage.new(input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 1_000_000)
    )

    assert_equal 50, entry.estimated_cost_cents
  end

  test "tolerates a usage object without cache fields" do
    entry = CostLedgerEntry.record!(
      workspace: @workspace, kind: "scoring", model: "claude-opus-5",
      usage: Struct.new(:input_tokens, :output_tokens).new(10, 20)
    )

    assert_equal 0, entry.cached_input_tokens
  end
end
