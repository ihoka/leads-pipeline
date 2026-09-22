require "test_helper"

class AnthropicClientTest < ActiveSupport::TestCase
  test "uses claude-opus-5" do
    assert_equal "claude-opus-5", AnthropicClient.model
  end

  test "builds a client" do
    assert_kind_of Anthropic::Client, AnthropicClient.instance
  end

  test "treats an exported but blank api key as unset" do
    original = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = ""
    AnthropicClient.reset!

    error = assert_raises(RuntimeError) { AnthropicClient.instance }

    assert_match "ANTHROPIC_API_KEY is not set", error.message
  ensure
    ENV["ANTHROPIC_API_KEY"] = original
    AnthropicClient.reset!
  end
end
