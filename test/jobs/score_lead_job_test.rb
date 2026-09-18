require "test_helper"

class ScoreLeadJobTest < ActiveJob::TestCase
  API_URL = "https://api.anthropic.com/v1/messages"

  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
    company = @workspace.companies.create!(name: "Acme", domain: "acme.com")
    company.evidences.create!(workspace: @workspace, attribute_name: "name", value: "Acme",
                              source_key: "hn_who_is_hiring", fetched_at: Time.current)
    @lead = Lead.create!(workspace: @workspace, company: company)
  end

  test "creates a score" do
    stub_ok

    assert_difference "Score.count", 1 do
      ScoreLeadJob.perform_now(@lead, @icp)
    end
  end

  test "does not re-score a lead already scored under the same icp version" do
    stub_ok
    ScoreLeadJob.perform_now(@lead, @icp)

    assert_no_difference "Score.count" do
      ScoreLeadJob.perform_now(@lead, @icp)
    end
  end

  test "leaves the lead unscored and does not raise when the API fails" do
    stub_request(:post, API_URL).to_return(status: 500, body: "{}")

    assert_no_difference "Score.count" do
      ScoreLeadJob.perform_now(@lead, @icp)
    end
  end

  private
    def stub_ok
      body = { total: 70, dimensions: { fit: 7 }, rationale: "r",
               cited_evidence_ids: [ @lead.company.evidences.first.id ], confidence: 0.7 }

      stub_request(:post, API_URL).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "m", type: "message", role: "assistant", model: "claude-opus-5",
                content: [ { type: "text", text: body.to_json } ], stop_reason: "end_turn",
                usage: { input_tokens: 10, output_tokens: 5 } }.to_json
      )
    end
end
