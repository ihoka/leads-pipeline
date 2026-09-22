require "test_helper"

class ReviewControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
    @lead = queued_lead("Acme Analytics", 88)
  end

  test "index renders the queue with the first lead selected" do
    get review_index_url

    assert_response :success
    assert_select "[data-lead-id='#{@lead.id}']"
    assert_match "Acme Analytics", response.body
  end

  test "index shows the score rationale and evidence" do
    get review_index_url

    assert_match "Scored because", response.body
  end

  test "index shows an empty state when nothing is queued" do
    @lead.update!(status: "disqualified")

    get review_index_url

    assert_response :success
    assert_match "Nothing to review", response.body
  end

  test "deciding advances the lead and removes it from the queue" do
    post decide_review_url(@lead), params: { decision: "advance", reason_code: "other" }

    assert_redirected_to review_index_url
    assert_equal "qualified", @lead.reload.status
    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "deciding records the reason code" do
    post decide_review_url(@lead), params: { decision: "disqualify", reason_code: "too_small" }

    assert_equal "too_small", ReviewDecision.sole.reason_code
  end

  test "deciding without a reason code is rejected and leaves the lead untouched" do
    post decide_review_url(@lead), params: { decision: "advance" }

    assert_response :bad_request
    assert_equal "new", @lead.reload.status
    assert_empty ReviewDecision.all
  end

  private
    def queued_lead(name, total)
      company = @workspace.companies.create!(name: name, domain: "acme.com")
      company.evidences.create!(workspace: @workspace, attribute_name: "name", value: name,
                                source_key: "hn_who_is_hiring",
                                source_url: "https://news.ycombinator.com/item?id=1",
                                fetched_at: Time.current)
      lead = Lead.create!(workspace: @workspace, company: company)
      Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp, total: total,
                    dimensions: { "fit" => 8, "timing" => 9 },
                    rationale: "Scored because they are hiring Rails engineers.",
                    cited_evidence_ids: [ company.evidences.first.id ], model: "claude-opus-5")
      lead
    end
end
