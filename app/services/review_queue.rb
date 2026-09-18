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
      .where("latest_scores.flagged_reason IS NULL")
      .where("NOT EXISTS (#{suppressed_company_sql})")
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
    #
    # flagged_reason rides along so the queue can filter on the current score's
    # flag: a lead whose newest score is fabricated must not fall back to an
    # older clean score and resurrect a stale number.
    def latest_score_join
      <<~SQL.squish
        INNER JOIN (
          SELECT DISTINCT ON (lead_id) lead_id, total, flagged_reason, created_at
          FROM scores
          ORDER BY lead_id, created_at DESC, id DESC
        ) AS latest_scores ON latest_scores.lead_id = leads.id
      SQL
    end

    # Suppression is checked at the surfacing point, not only at ingest: an
    # opt-out recorded today has to remove the lead discovered yesterday. The
    # comparison is case-insensitive to match Suppression.suppressed?, and a
    # company with no domain can never match one, so it still surfaces.
    def suppressed_company_sql
      <<~SQL.squish
        SELECT 1 FROM suppressions
        INNER JOIN companies ON lower(companies.domain) = lower(suppressions.domain)
        WHERE suppressions.workspace_id = leads.workspace_id
          AND companies.id = leads.company_id
      SQL
    end
end
