module Scoring
  class Scorer
    ScoringFailed = Class.new(StandardError)
    MAX_TOKENS = 2_000

    def initialize(lead:, icp_definition:)
      @lead = lead
      @icp = icp_definition
      @prompt = RubricPrompt.new(icp_definition)
    end

    def call
      response = request
      parsed = parse(response)

      CostLedgerEntry.record!(
        workspace: @lead.workspace, kind: "scoring",
        model: AnthropicClient.model, usage: response.usage, subject: @lead
      )

      build_score(parsed)
    rescue ActiveRecord::RecordInvalid, NoMethodError => error
      raise ScoringFailed, "scoring lead #{@lead.id} produced an invalid record: #{error.class}: #{error.message}"
    end

    private
      def request
        AnthropicClient.instance.messages.create(
          model: AnthropicClient.model,
          max_tokens: MAX_TOKENS,
          system_: @prompt.system_prompt,
          messages: [ { role: "user", content: @prompt.user_prompt(@lead) } ],
          thinking: { type: "adaptive" },
          cache_control: { type: "ephemeral" },
          output_config: { format_: { type: :json_schema, schema: RubricPrompt::SCHEMA } }
        )
      rescue Anthropic::Errors::APIError => error
        raise ScoringFailed, "scoring lead #{@lead.id} failed: #{error.class}: #{error.message}"
      end

      def parse(response)
        text = response.content.find { |block| block.type == :text }&.text
        raise ScoringFailed, "no text block in response for lead #{@lead.id}" if text.blank?

        JSON.parse(text)
      rescue JSON::ParserError => error
        raise ScoringFailed, "unparseable scoring response for lead #{@lead.id}: #{error.message}"
      end

      def build_score(parsed)
        cited = Array(parsed["cited_evidence_ids"]).map(&:to_i)

        Score.create!(
          workspace: @lead.workspace,
          lead: @lead,
          icp_definition: @icp,
          total: parsed["total"],
          dimensions: parsed["dimensions"] || {},
          rationale: parsed["rationale"],
          cited_evidence_ids: cited,
          confidence: parsed["confidence"],
          model: AnthropicClient.model,
          flagged_reason: EvidenceValidator.new(lead: @lead, cited_ids: cited).failure_reason
        )
      end
  end
end
