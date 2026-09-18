require "test_helper"

class AnthropicClientTest < ActiveSupport::TestCase
  test "uses claude-opus-5" do
    assert_equal "claude-opus-5", AnthropicClient.model
  end

  test "builds a client" do
    assert_kind_of Anthropic::Client, AnthropicClient.instance
  end
end
