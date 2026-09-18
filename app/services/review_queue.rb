# Assembles the capped daily review surface.
#
# The cap is the point: an unbounded queue is an ignored queue. Leads below the
# threshold remain available in the full list view but never compete for the
# operator's morning.
class ReviewQueue
  CAP = 20
  THRESHOLD = 40

  def initialize(workspace:)
    @workspace = workspace
  end

  def leads
    @workspace.leads
      .where(status: "new")
      .where("leads.snoozed_until IS NULL OR leads.snoozed_until <= ?", Time.current)
      .joins(latest_score_join)
      .where("latest_scores.total >= ?", THRESHOLD)
      .includes(:company)
      .order(Arel.sql("latest_scores.total DESC"))
      .limit(CAP)
      .to_a
  end

  private
    # DISTINCT ON gives us one row per lead — the newest score — which is what
    # "the lead's current score" means given that scores are append-only. The
    # id tiebreaker matches Lead#latest_score so the queue and detail view
    # agree on which score is "current" even when two scores share a
    # created_at timestamp.
    def latest_score_join
      <<~SQL.squish
        INNER JOIN (
          SELECT DISTINCT ON (lead_id) lead_id, total, created_at
          FROM scores
          ORDER BY lead_id, created_at DESC, id DESC
        ) AS latest_scores ON latest_scores.lead_id = leads.id
      SQL
    end
end
