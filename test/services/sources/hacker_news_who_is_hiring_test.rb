require "test_helper"

class Sources::HackerNewsWhoIsHiringTest < ActiveSupport::TestCase
  STORIES_URL = "https://hn.algolia.com/api/v1/search_by_date"

  setup do
    @adapter = Sources::HackerNewsWhoIsHiring.new
    stub_stories
    stub_comments
  end

  test "is registered under its key" do
    assert_equal Sources::HackerNewsWhoIsHiring, Sources::Registry.fetch("hn_who_is_hiring")
  end

  test "returns only top-level job posts" do
    hits = @adapter.search({})

    assert_equal 1, hits.length
    assert_equal "49523001", hits.first.source_uid
  end

  test "preserves the payload verbatim" do
    hit = @adapter.search({}).first

    assert_equal "ceo_acme", hit.payload["author"]
    assert_includes hit.payload["comment_text"], "Acme Analytics"
  end

  test "sets observed_at from the comment timestamp" do
    hit = @adapter.search({}).first

    assert_equal Time.parse("2026-09-01T16:00:00Z"), hit.observed_at
  end

  test "selects the hiring thread and not the wants-to-be-hired thread" do
    @adapter.search({})

    assert_requested :get, STORIES_URL, query: hash_including("tags" => "comment,story_49522897")
  end

  test "raises when no hiring thread can be found" do
    stub_request(:get, STORIES_URL)
      .with(query: hash_including("tags" => "story,author_whoishiring"))
      .to_return(body: { "hits" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Sources::HackerNewsWhoIsHiring::ThreadNotFound) { @adapter.search({}) }
  end

  test "raises on a non-success response" do
    stub_request(:get, STORIES_URL)
      .with(query: hash_including("tags" => "story,author_whoishiring"))
      .to_return(status: 503)

    assert_raises(Sources::HackerNewsWhoIsHiring::RequestFailed) { @adapter.search({}) }
  end

  test "collects top-level posts across multiple pages" do
    stub_request(:get, STORIES_URL)
      .with(query: hash_including("tags" => "comment,story_49522897", "page" => "0"))
      .to_return(
        body: {
          "nbPages" => 2,
          "hits" => [
            {
              "objectID" => "49523001",
              "author" => "ceo_acme",
              "comment_text" => "Acme Analytics | Senior Rails Engineer | REMOTE",
              "created_at" => "2026-09-01T16:00:00Z",
              "parent_id" => 49522897,
              "story_id" => 49522897,
              "story_title" => "Ask HN: Who is hiring? (September 2026)"
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, STORIES_URL)
      .with(query: hash_including("tags" => "comment,story_49522897", "page" => "1"))
      .to_return(
        body: {
          "nbPages" => 2,
          "hits" => [
            {
              "objectID" => "49523099",
              "author" => "cto_beta",
              "comment_text" => "Beta Systems | Staff Engineer | REMOTE",
              "created_at" => "2026-09-01T17:00:00Z",
              "parent_id" => 49522897,
              "story_id" => 49522897,
              "story_title" => "Ask HN: Who is hiring? (September 2026)"
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    hits = @adapter.search({})

    assert_equal %w[49523001 49523099], hits.map(&:source_uid)
  end

  private
    def stub_stories
      stub_request(:get, STORIES_URL)
        .with(query: hash_including("tags" => "story,author_whoishiring"))
        .to_return(
          body: file_fixture("hn_stories.json").read,
          headers: { "Content-Type" => "application/json" }
        )
    end

    def stub_comments
      stub_request(:get, STORIES_URL)
        .with(query: hash_including("tags" => "comment,story_49522897"))
        .to_return(
          body: file_fixture("hn_comments.json").read,
          headers: { "Content-Type" => "application/json" }
        )
    end
end
