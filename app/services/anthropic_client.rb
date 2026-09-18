# Single configured Claude client. Model choice is deliberately centralised:
# routing cheaper stages to a smaller model is a cost lever to pull with
# measurements in hand, not a default to drift into.
module AnthropicClient
  MODEL = "claude-opus-5".freeze

  class << self
    def instance
      @instance ||= Anthropic::Client.new(api_key: api_key)
    end

    def model = MODEL

    def reset! = @instance = nil

    private
      # An exported-but-blank key is treated as unset: on Fly a blank secret
      # would otherwise build a client that 401s on every call, which surfaces
      # as zero scores and no signal at all.
      def api_key
        ENV["ANTHROPIC_API_KEY"].presence ||
          Rails.application.credentials.dig(:anthropic, :api_key).presence ||
          raise("ANTHROPIC_API_KEY is not set")
      end
  end
end
