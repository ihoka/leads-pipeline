require "test_helper"

class Normalizers::HackerNewsPostTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    icp = search.icp_definitions.create!(brief: "b")
    run = search.runs.create!(workspace: @workspace, icp_definition: icp)
    @execution = run.run_source_executions.create!(workspace: @workspace, source_key: "hn_who_is_hiring")
  end

  test "extracts company name, domain, and location from a conventional header" do
    result = normalize(
      "Acme Analytics (https:&#x2F;&#x2F;acme.com) | Senior Rails Engineer | REMOTE | Bristol, UK<p>We are hiring."
    )

    assert_equal "Acme Analytics", result.company_attrs[:name]
    assert_equal "acme.com", result.company_attrs[:domain]
    assert_equal "Bristol, UK", result.company_attrs[:location]
  end

  test "produces a domain identifier and a normalized name identifier" do
    result = normalize("Acme Analytics (https:&#x2F;&#x2F;acme.com) | Engineer | Bristol")

    assert_includes result.identifiers, { kind: "domain", value: "acme.com" }
    assert_includes result.identifiers, { kind: "normalized_name", value: "acme analytics" }
  end

  test "falls back to the name alone when there is no url" do
    result = normalize("Basalt Interactive | Backend Engineer | Berlin")

    assert_equal "Basalt Interactive", result.company_attrs[:name]
    assert_nil result.company_attrs[:domain]
    assert_equal [ { kind: "normalized_name", value: "basalt interactive" } ], result.identifiers
  end

  test "strips www and trailing slashes from the domain" do
    result = normalize("Acme (https:&#x2F;&#x2F;www.acme.com&#x2F;) | Engineer")

    assert_equal "acme.com", result.company_attrs[:domain]
  end

  test "builds evidence for every extracted attribute" do
    result = normalize("Acme Analytics (https:&#x2F;&#x2F;acme.com) | Engineer | REMOTE | Bristol, UK")
    names = result.evidence_attrs.map { |e| e[:attribute_name] }

    assert_includes names, "name"
    assert_includes names, "domain"
    assert_includes names, "location"
    assert(result.evidence_attrs.all? { |e| e[:source_key] == "hn_who_is_hiring" })
    assert(result.evidence_attrs.all? { |e| e[:source_url].present? })
  end

  test "evidence links back to the hacker news comment" do
    result = normalize("Acme (https:&#x2F;&#x2F;acme.com) | Engineer")

    assert_equal "https://news.ycombinator.com/item?id=49523001",
                 result.evidence_attrs.first[:source_url]
  end

  test "returns a blank result when the post has no parseable header" do
    result = normalize("we are looking for people, email me")

    assert_nil result.company_attrs[:name]
    assert_empty result.identifiers
    assert_empty result.evidence_attrs
  end

  # --- Task 6b: real thread formats -----------------------------------------
  # Algolia renders every URL in the live thread as an <a href="..."> anchor,
  # not the bare parenthesised URL the plan's idealised fixtures assumed.

  test "extracts domain from an anchor href in a trailing pipe segment (Lumen Labs, live)" do
    result = normalize(
      "Lumen Labs | Robotics &#x2F; Hardware Engineer | San Francisco, CA | ONSITE | " \
      "Full-time | $130k–200k + equity | <a href=\"https:&#x2F;&#x2F;lumenresearch.co\" " \
      "rel=\"nofollow\">https:&#x2F;&#x2F;lumenresearch.co</a>"
    )

    assert_equal "lumenresearch.co", result.company_attrs[:domain]
  end

  test "extracts domain from a parenthesised anchor href (Tether, live)" do
    # The brief's live excerpt is elided ("...") after "we're hiring!"; a trailing
    # pipe segment is appended here only so the header has the >1 segments `name`
    # requires, without altering the quoted anchor markup itself.
    result = normalize(
      "At Tether (<a href=\"https:&#x2F;&#x2F;tether.io&#x2F;\" rel=\"nofollow\">" \
      "https:&#x2F;&#x2F;tether.io&#x2F;</a>) we&#x27;re hiring! | Founding Engineer | Remote"
    )

    assert_equal "tether.io", result.company_attrs[:domain]
  end

  test "does not treat a news.ycombinator.com link as the company domain" do
    result = normalize(
      "Globex Corp (<a href=\"https://news.ycombinator.com/item?id=12345\" rel=\"nofollow\">" \
      "https://news.ycombinator.com/item?id=12345</a>) | Backend Engineer | Remote"
    )

    assert_nil result.company_attrs[:domain]
  end

  test "does not capture a salary range as the location (Anterior-shaped, live)" do
    result = normalize(
      "Anterior | Machine Learning Engineer | New York, NY | $230,000–$300,000 + equity | Onsite"
    )

    assert_equal "New York, NY", result.company_attrs[:location]
  end

  test "extracts the real location from the Lumen Labs header, not the compensation segment" do
    result = normalize(
      "Lumen Labs | Robotics &#x2F; Hardware Engineer | San Francisco, CA | ONSITE | " \
      "Full-time | $130k–200k + equity | <a href=\"https:&#x2F;&#x2F;lumenresearch.co\" " \
      "rel=\"nofollow\">https:&#x2F;&#x2F;lumenresearch.co</a>"
    )

    assert_equal "San Francisco, CA", result.company_attrs[:location]
  end

  test "does not capture the role slot as the location (Remote | Senior/Staff Backend Engineer, X shape)" do
    result = normalize("Remote | Senior/Staff Backend Engineer, Platform | REMOTE | Full-time")

    assert_nil result.company_attrs[:location]
  end

  private
    def normalize(comment_text)
      raw_hit = @execution.raw_hits.create!(
        workspace: @workspace,
        source_key: "hn_who_is_hiring",
        source_uid: "49523001",
        payload: { "objectID" => "49523001", "comment_text" => comment_text,
                   "created_at" => "2026-09-01T16:00:00Z" },
        fetched_at: Time.current
      )
      Normalizers::HackerNewsPost.new(raw_hit).call
    end
end
