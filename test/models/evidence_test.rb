require "test_helper"

class EvidenceTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @company = @workspace.companies.create!(name: "Acme")
  end

  test "records provenance for a company attribute" do
    evidence = @company.evidences.create!(
      workspace: @workspace,
      attribute_name: "location",
      value: "Bristol, UK",
      source_key: "hn_who_is_hiring",
      source_url: "https://news.ycombinator.com/item?id=1",
      fetched_at: Time.current
    )

    assert evidence.persisted?
    assert_equal @company, evidence.subject
  end

  test "requires a source key" do
    evidence = @company.evidences.build(
      workspace: @workspace, attribute_name: "location", value: "x", fetched_at: Time.current
    )
    refute evidence.valid?
  end
end
