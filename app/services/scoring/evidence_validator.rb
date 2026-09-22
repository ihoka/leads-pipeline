module Scoring
  # Guards against the most dangerous failure in the system: a model that
  # invents the justification for its own score. The output of such a failure
  # looks entirely correct, so it must be caught mechanically rather than by
  # reading.
  class EvidenceValidator
    def initialize(lead:, cited_ids:)
      @lead = lead
      @cited_ids = Array(cited_ids).map(&:to_i)
    end

    def failure_reason
      return "model cited no evidence despite #{available_ids.size} records being available" if missing_citations?
      return nil if unknown_ids.empty?

      "model cited evidence ids that do not belong to this lead: #{unknown_ids.join(', ')}"
    end

    private
      def available_ids
        @available_ids ||= @lead.company.evidences.pluck(:id)
      end

      def missing_citations?
        @cited_ids.empty? && available_ids.any?
      end

      def unknown_ids
        @unknown_ids ||= @cited_ids - available_ids
      end
  end
end
