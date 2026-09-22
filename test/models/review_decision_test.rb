require "test_helper"

class ReviewDecisionTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    company = @workspace.companies.create!(name: "Acme")
    @lead = Lead.create!(workspace: @workspace, company: company)
  end

  test "advancing marks the lead qualified" do
    ReviewDecision.record!(lead: @lead, decision: "advance", reason_code: "other")

    assert_equal "qualified", @lead.reload.status
  end

  test "disqualifying marks the lead disqualified" do
    ReviewDecision.record!(lead: @lead, decision: "disqualify", reason_code: "too_small")

    assert_equal "disqualified", @lead.reload.status
  end

  test "snoozing sets a future date and leaves the lead new" do
    ReviewDecision.record!(lead: @lead, decision: "snooze", reason_code: "not_now", snooze_days: 90)

    assert_equal "new", @lead.reload.status
    assert_in_delta 90.days.from_now.to_i, @lead.snoozed_until.to_i, 60
  end

  test "rejects an unknown reason code" do
    assert_raises(ActiveRecord::RecordInvalid) do
      ReviewDecision.record!(lead: @lead, decision: "disqualify", reason_code: "nonsense")
    end
  end
end
