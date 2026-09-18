require "test_helper"

class ReviewQueueTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
  end

  test "includes new leads scoring at or above the threshold" do
    high = lead_with_score(80)
    lead_with_score(10)

    assert_equal [ high ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "orders by score descending" do
    low = lead_with_score(55)
    high = lead_with_score(90)

    assert_equal [ high, low ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "caps the queue" do
    (ReviewQueue::CAP + 5).times { lead_with_score(70) }

    assert_equal ReviewQueue::CAP, ReviewQueue.new(workspace: @workspace).leads.size
  end

  test "excludes leads that are not new" do
    lead = lead_with_score(80)
    lead.update!(status: "disqualified")

    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "excludes a lead snoozed into the future" do
    lead = lead_with_score(80)
    lead.update!(snoozed_until: 3.days.from_now)

    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "includes a lead whose snooze has expired" do
    lead = lead_with_score(80)
    lead.update!(snoozed_until: 1.day.ago)

    assert_equal [ lead ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "excludes unscored leads" do
    company = @workspace.companies.create!(name: "Unscored")
    Lead.create!(workspace: @workspace, company: company)

    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "uses only the most recent score" do
    lead = lead_with_score(10)
    Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp,
                  total: 90, rationale: "rescored", model: "claude-opus-5")

    assert_equal [ lead ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "excludes a lead whose current score is flagged" do
    lead_with_score(90, flagged_reason: "model cited evidence ids that do not belong to this lead: 999")

    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "includes a lead whose current score is clean but whose earlier score was flagged" do
    lead = lead_with_score(50, flagged_reason: "fabricated citation")
    Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp,
                  total: 80, rationale: "rescored", model: "claude-opus-5")

    assert_equal [ lead ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "excludes a lead whose company domain was suppressed after discovery" do
    lead = lead_with_score(80, domain: "acme.com")
    assert_equal [ lead ], ReviewQueue.new(workspace: @workspace).leads

    @workspace.suppressions.create!(domain: "ACME.com", reason: "opted_out")

    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "includes a lead whose company has no domain when a suppression exists" do
    lead = lead_with_score(80)
    @workspace.suppressions.create!(domain: "acme.com", reason: "opted_out")

    assert_nil lead.company.domain
    assert_equal [ lead ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "ignores a suppression belonging to another workspace" do
    lead = lead_with_score(80, domain: "acme.com")
    other = Workspace.create!(name: "Other")
    other.suppressions.create!(domain: "acme.com", reason: "opted_out")

    assert_equal [ lead ], ReviewQueue.new(workspace: @workspace).leads
  end

  private
    def lead_with_score(total, domain: nil, flagged_reason: nil)
      company = @workspace.companies.create!(name: "Co #{SecureRandom.hex(4)}", domain: domain)
      lead = Lead.create!(workspace: @workspace, company: company)
      Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp,
                    total: total, rationale: "r", model: "claude-opus-5",
                    flagged_reason: flagged_reason)
      lead
    end
end
