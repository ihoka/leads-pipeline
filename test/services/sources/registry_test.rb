require "test_helper"

class Sources::RegistryTest < ActiveSupport::TestCase
  class FakeAdapter < Sources::Adapter
    def self.key = "fake"

    def self.manifest
      Sources::Manifest.new(
        accepted_params: [ :query ], returned_fields: [ :name ],
        cost_cents_per_call: 0, risk_level: :none
      )
    end

    def search(params)
      [ Sources::Hit.new(source_uid: "1", payload: { "q" => params[:query] }, observed_at: Time.current) ]
    end
  end

  setup { Sources::Registry.register(FakeAdapter) }
  teardown { Sources::Registry.reset! }

  test "fetches a registered adapter by key" do
    assert_equal FakeAdapter, Sources::Registry.fetch("fake")
  end

  test "raises a helpful error for an unknown key" do
    error = assert_raises(Sources::Registry::UnknownAdapter) { Sources::Registry.fetch("nope") }
    assert_match "nope", error.message
  end

  test "lists registered keys" do
    assert_includes Sources::Registry.keys, "fake"
  end

  test "an adapter returns hits" do
    hits = FakeAdapter.new.search(query: "rails")

    assert_equal 1, hits.length
    assert_equal "1", hits.first.source_uid
    assert_equal({ "q" => "rails" }, hits.first.payload)
  end

  test "the base adapter refuses to search" do
    assert_raises(NotImplementedError) { Sources::Adapter.new.search({}) }
  end
end
