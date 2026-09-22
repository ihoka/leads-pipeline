require "application_system_test_case"

class TriageTest < ApplicationSystemTestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
    @first = queued_lead("Alpha Corp", 90)
    @second = queued_lead("Beta Corp", 80)
  end

  test "j moves selection down and k moves it back up" do
    visit review_index_path

    assert_selector "[data-lead-id='#{@first.id}'].is-selected"

    find("body").send_keys("j")
    assert_selector "[data-lead-id='#{@second.id}'].is-selected"

    find("body").send_keys("k")
    assert_selector "[data-lead-id='#{@first.id}'].is-selected"
  end

  test "d disqualifies the selected lead" do
    visit review_index_path
    find("body").send_keys("d")

    assert_no_selector "[data-lead-id='#{@first.id}']"
    assert_equal "disqualified", @first.reload.status
  end

  private
    def queued_lead(name, total)
      company = @workspace.companies.create!(name: name, domain: "#{name.parameterize}.com")
      company.evidences.create!(workspace: @workspace, attribute_name: "name", value: name,
                                source_key: "hn_who_is_hiring", fetched_at: Time.current)
      lead = Lead.create!(workspace: @workspace, company: company)
      Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp, total: total,
                    rationale: "r", cited_evidence_ids: [ company.evidences.first.id ],
                    model: "claude-opus-5")
      lead
    end
end
