require "test_helper"

class Scoring::EvidenceValidatorTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @company = @workspace.companies.create!(name: "Acme")
    @evidence = @company.evidences.create!(
      workspace: @workspace, attribute_name: "name", value: "Acme",
      source_key: "hn_who_is_hiring", fetched_at: Time.current
    )
    @lead = Lead.create!(workspace: @workspace, company: @company)
  end

  test "passes when every cited id belongs to the lead" do
    validator = Scoring::EvidenceValidator.new(lead: @lead, cited_ids: [ @evidence.id ])

    assert_nil validator.failure_reason
  end

  test "fails when an id does not exist" do
    validator = Scoring::EvidenceValidator.new(lead: @lead, cited_ids: [ @evidence.id, 999_999 ])

    assert_match "999999", validator.failure_reason
  end

  test "fails when an id belongs to another company" do
    other = @workspace.companies.create!(name: "Other")
    foreign = other.evidences.create!(
      workspace: @workspace, attribute_name: "name", value: "Other",
      source_key: "hn_who_is_hiring", fetched_at: Time.current
    )
    validator = Scoring::EvidenceValidator.new(lead: @lead, cited_ids: [ foreign.id ])

    assert_match foreign.id.to_s, validator.failure_reason
  end

  test "fails when nothing is cited but evidence exists" do
    validator = Scoring::EvidenceValidator.new(lead: @lead, cited_ids: [])

    assert_match "cited no evidence", validator.failure_reason
  end

  test "passes when nothing is cited and no evidence exists" do
    bare_company = @workspace.companies.create!(name: "Bare")
    bare_lead = Lead.create!(workspace: @workspace, company: bare_company)
    validator = Scoring::EvidenceValidator.new(lead: bare_lead, cited_ids: [])

    assert_nil validator.failure_reason
  end
end
