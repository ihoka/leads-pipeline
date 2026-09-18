module Scoring
  class Scorer
    ScoringFailed = Class.new(StandardError)
    MAX_TOKENS = 2_000

    def initialize(lead:, icp_definition:)
      @lead = lead
      @icp = icp_definition
      @prompt = RubricPrompt.new(icp_definition)
    end

    # The ledger entry is written as soon as the response arrives, before it is
    # parsed: a response that cannot be parsed was still paid for, and the
    # ledger is the only spend control we have. Under-reporting spend exactly
    # when the model is misbehaving is the wrong way round.
    def call
      response = request

      CostLedgerEntry.record!(
        workspace: @lead.workspace, kind: "scoring",
        model: AnthropicClient.model, usage: response.usage, subject: @lead
      )

      build_score(parse(response))
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
        cited = cited_evidence_ids(parsed)

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
      rescue ActiveRecord::RecordInvalid => error
        raise ScoringFailed, "scoring lead #{@lead.id} produced an invalid record: #{error.class}: #{error.message}"
      end

      # The model is schema-constrained but not schema-guaranteed: returning an
      # object where cited_evidence_ids should be an array makes the coercion
      # below raise. That one shape mismatch is a scoring failure; the rescue is
      # kept this narrow so a NoMethodError anywhere else in this class is a bug
      # and propagates loudly rather than being relabelled a scoring failure.
      def cited_evidence_ids(parsed)
        Array(parsed["cited_evidence_ids"]).map(&:to_i)
      rescue NoMethodError => error
        raise ScoringFailed,
          "scoring lead #{@lead.id} returned unusable cited_evidence_ids: #{error.class}: #{error.message}"
      end
  end
end
