require "test_helper"

class RunSearchJobTest < ActiveJob::TestCase
  STORIES_URL = "https://hn.algolia.com/api/v1/search_by_date"

  setup do
    @workspace = Workspace.create!(name: "Personal")
    @search = @workspace.searches.create!(name: "HN", status: "active")
    @search.icp_definitions.create!(brief: "Funded startups needing Rails help")
    @search.search_sources.create!(workspace: @workspace, adapter_key: "hn_who_is_hiring")
    stub_hn
  end

  test "creates a completed run pinned to the active icp definition" do
    RunSearchJob.perform_now(@search)
    run = @search.runs.sole

    assert_equal "completed", run.status
    assert_equal @search.active_icp_definition, run.icp_definition
    assert run.finished_at.present?
  end

  test "stores raw hits verbatim" do
    RunSearchJob.perform_now(@search)

    assert_equal 1, RawHit.count
    assert_equal "49523001", RawHit.sole.source_uid
  end

  test "creates a company with evidence for each attribute" do
    RunSearchJob.perform_now(@search)
    company = Company.sole

    assert_equal "Acme Analytics", company.name
    assert_equal "acme.com", company.domain
    assert_equal %w[domain location name], company.evidences.order(:attribute_name).pluck(:attribute_name)
  end

  test "creates one lead and records its discovery" do
    RunSearchJob.perform_now(@search)

    assert_equal 1, Lead.count
    assert_equal "new", Lead.sole.status
    assert_equal @search, LeadDiscovery.sole.search
  end

  test "a second run does not duplicate the lead but records a second discovery" do
    RunSearchJob.perform_now(@search)
    RunSearchJob.perform_now(@search)

    assert_equal 1, Lead.count
    assert_equal 2, LeadDiscovery.count
  end

  test "records per-source failure without failing the run" do
    stub_request(:get, STORIES_URL).with(query: hash_including({})).to_return(status: 503)

    RunSearchJob.perform_now(@search)
    run = @search.runs.sole

    assert_equal "completed", run.status
    assert_equal "failed", run.run_source_executions.sole.status
    assert_match "503", run.run_source_executions.sole.error_message
  end

  test "records run statistics" do
    RunSearchJob.perform_now(@search)

    assert_equal 1, @search.runs.sole.stats["hits_found"]
    assert_equal 1, @search.runs.sole.stats["leads_created"]
  end

  test "does not create a lead for a suppressed domain" do
    @workspace.suppressions.create!(domain: "acme.com", reason: "current_client")

    RunSearchJob.perform_now(@search)

    assert_equal 0, Lead.count
    assert_equal 1, @search.runs.sole.stats["suppressed"]
  end

  private
    def stub_hn
      stub_request(:get, STORIES_URL)
        .with(query: hash_including("tags" => "story,author_whoishiring"))
        .to_return(body: file_fixture("hn_stories.json").read,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, STORIES_URL)
        .with(query: hash_including("tags" => "comment,story_49522897"))
        .to_return(body: file_fixture("hn_comments.json").read,
                   headers: { "Content-Type" => "application/json" })
    end
end
