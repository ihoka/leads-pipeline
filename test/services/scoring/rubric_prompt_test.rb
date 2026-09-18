require "test_helper"

class Scoring::RubricPromptTest < ActiveSupport::TestCase
  MARKER = /<(UNTRUSTED_DATA_[0-9a-f]{16})>/

  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "Funded startups needing Rails help")
    @company = @workspace.companies.create!(name: "Acme Analytics", domain: "acme.com")
    @evidence = @company.evidences.create!(
      workspace: @workspace, attribute_name: "name", value: "Acme Analytics",
      source_key: "hn_who_is_hiring", source_url: "https://news.ycombinator.com/item?id=1",
      fetched_at: Time.current
    )
    @lead = Lead.create!(workspace: @workspace, company: @company)
    @prompt = Scoring::RubricPrompt.new(@icp)
  end

  test "encloses the company block as well as the evidence in the untrusted markers" do
    body = @prompt.user_prompt(@lead)
    marker = body[MARKER, 1]

    assert marker.present?, "expected a nonce marker in #{body}"
    inner = body[/<#{marker}>(.*)<\/#{marker}>/m, 1]
    assert_includes inner, "Name: Acme Analytics"
    assert_includes inner, "Domain: acme.com"
    assert_includes inner, "id=#{@evidence.id}"
  end

  test "uses a fresh marker for every request" do
    markers = 3.times.map { @prompt.user_prompt(@lead)[MARKER, 1] }

    assert_equal 3, markers.uniq.size
  end

  test "keeps the marker out of the cacheable system prefix" do
    marker = @prompt.user_prompt(@lead)[MARKER, 1]

    assert_no_match(/UNTRUSTED_DATA_/, @prompt.system_prompt)
    assert_not_includes @prompt.system_prompt, marker
    assert_includes @prompt.system_prompt, "untrusted third-party data"
  end
end
