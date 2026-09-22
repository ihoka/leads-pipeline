require "test_helper"

class ScoreTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
    company = @workspace.companies.create!(name: "Acme")
    @lead = Lead.create!(workspace: @workspace, company: company)
  end

  test "is append-only" do
    score = Score.create!(
      workspace: @workspace, lead: @lead, icp_definition: @icp,
      total: 80, dimensions: { "fit" => 8 }, rationale: "r", model: "claude-opus-5"
    )

    assert_raises(ActiveRecord::ReadOnlyRecord) { score.update!(total: 90) }
  end

  test "lead exposes its latest score" do
    Score.create!(workspace: @workspace, lead: @lead, icp_definition: @icp,
                  total: 50, rationale: "old", model: "claude-opus-5")
    newest = Score.create!(workspace: @workspace, lead: @lead, icp_definition: @icp,
                           total: 80, rationale: "new", model: "claude-opus-5")

    assert_equal newest, @lead.reload.latest_score
  end

  test "rejects a total outside 0..100" do
    score = Score.new(workspace: @workspace, lead: @lead, icp_definition: @icp,
                      total: 120, rationale: "r", model: "claude-opus-5")
    refute score.valid?
  end

  test "destroying a lead with a score does not raise and removes the score" do
    score = Score.create!(workspace: @workspace, lead: @lead, icp_definition: @icp,
                          total: 80, rationale: "r", model: "claude-opus-5")

    assert_nothing_raised { @lead.destroy! }

    refute Score.exists?(score.id)
  end
end
