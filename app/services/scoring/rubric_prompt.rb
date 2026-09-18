module Scoring
  # Builds the scoring prompt. The rubric and ICP form a stable prefix that is
  # identical for every lead in a run, so it caches; only the lead's evidence
  # varies and it goes last.
  class RubricPrompt
    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[total dimensions rationale cited_evidence_ids confidence],
      properties: {
        total: { type: "integer", minimum: 0, maximum: 100 },
        dimensions: {
          type: "object",
          additionalProperties: { type: "integer", minimum: 0, maximum: 10 }
        },
        rationale: { type: "string" },
        cited_evidence_ids: { type: "array", items: { type: "integer" } },
        confidence: { type: "number", minimum: 0, maximum: 1 }
      }
    }.freeze

    INSTRUCTIONS = <<~TEXT.freeze
      You score inbound sales leads for a software development consultancy.

      You will be given an ideal client profile and a set of evidence records
      about one company. Each evidence record has a numeric id.

      Rules:
      - Score each dimension from 0 to 10, and give a total from 0 to 100.
      - Cite the id of every evidence record that informed your score in
        cited_evidence_ids. Cite only ids that appear in the evidence you were
        given. Never invent an id.
      - If the evidence is too thin to judge, say so in the rationale and
        return a low confidence rather than guessing.
      - Judge fit against the profile, not general company quality. A large
        successful company that does not need outside help is a poor lead.
    TEXT

    def initialize(icp_definition)
      @icp = icp_definition
    end

    # Stable across every lead in a run, so it is the cacheable prefix.
    def system_prompt
      <<~TEXT
        #{INSTRUCTIONS}

        ## Ideal client profile

        #{@icp.brief}

        ## Scoring dimensions and weights

        #{rubric_description}
      TEXT
    end

    # Varies per lead, so it goes in the user message, after the cached prefix.
    def user_prompt(lead)
      evidence = lead.company.evidences.order(:id).map do |record|
        "- id=#{record.id} #{record.attribute_name}: #{record.value} " \
          "(source: #{record.source_key}, observed #{record.fetched_at.to_date})"
      end

      <<~TEXT
        ## Company

        Name: #{lead.company.name}
        Domain: #{lead.company.domain || 'unknown'}
        Location: #{lead.company.location || 'unknown'}

        ## Evidence

        #{evidence.join("\n").presence || '(no evidence recorded)'}
      TEXT
    end

    private
      def rubric_description
        dimensions = @icp.scoring_rubric["dimensions"].presence ||
          { "fit" => 40, "timing" => 35, "reachability" => 25 }

        dimensions.map { |name, weight| "- #{name} (weight #{weight})" }.join("\n")
      end
  end
end
