require "test_helper"

class LeadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @company = @workspace.companies.create!(name: "Acme Analytics", domain: "acme.com")
    @lead = Lead.create!(workspace: @workspace, company: @company)
    @company.evidences.create!(
      workspace: @workspace, attribute_name: "domain", value: "acme.com",
      source_key: "hn_who_is_hiring",
      source_url: "https://news.ycombinator.com/item?id=1", fetched_at: Time.current
    )
  end

  test "index lists leads" do
    get leads_url

    assert_response :success
    assert_select "[data-lead-id='#{@lead.id}']"
    assert_match "Acme Analytics", response.body
  end

  test "show displays the company and its evidence with source links" do
    get lead_url(@lead)

    assert_response :success
    assert_match "acme.com", response.body
    assert_select "a[href='https://news.ycombinator.com/item?id=1']"
  end
end
