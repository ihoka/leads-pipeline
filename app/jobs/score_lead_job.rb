# Scores one lead. A scoring failure is logged and swallowed: an unscored lead
# is simply absent from tomorrow's queue, whereas a raising job would retry
# against a model call that costs money each attempt.
class ScoreLeadJob < ApplicationJob
  queue_as :default

  def perform(lead, icp_definition)
    return if already_scored?(lead, icp_definition)

    Scoring::Scorer.new(lead: lead, icp_definition: icp_definition).call
  rescue Scoring::Scorer::ScoringFailed => error
    Rails.logger.error(error.message)
  end

  private
    def already_scored?(lead, icp_definition)
      lead.scores.exists?(icp_definition: icp_definition)
    end
end
