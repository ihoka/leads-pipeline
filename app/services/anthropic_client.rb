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
      def api_key
        ENV.fetch("ANTHROPIC_API_KEY") do
          Rails.application.credentials.dig(:anthropic, :api_key) ||
            raise("ANTHROPIC_API_KEY is not set")
        end
      end
  end
end
