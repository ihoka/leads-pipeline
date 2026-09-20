# Development-only synthetic scores, so the triage inbox can be exercised
# without spending money on real model calls.
#
#   bin/rails runner db/seeds/demo_scores.rb
#
# Every rule the review queue applies gets at least one lead demonstrating it,
# including the ones whose correct behaviour is *exclusion* — a queue that only
# ever shows leads tells you nothing about the filters.
#
# Citations point at evidence rows that genuinely belong to each lead's company,
# so Scoring::EvidenceValidator passes them and flagged_reason stays nil. The one
# deliberately fabricated citation is the exception, and it proves the validator
# fires.
#
# Note: ScoreLeadJob#already_scored? skips a lead that already has a score under
# the same ICP version, so seeding here means a later real scoring run will leave
# these leads alone. Clear them first if you want real scores.

abort "Refusing to run outside development (RAILS_ENV=#{Rails.env})" unless Rails.env.development?

workspace = Workspace.first!
icp = Search.first!.active_icp_definition
abort "No ICP definition — run bin/rails db:seed first" if icp.nil?

# Scores are append-only at the model layer, so a re-run would stack a second
# generation on top of the first. delete_all bypasses that guard deliberately:
# this is a development fixture, and predictability beats fidelity here.
cleared = Score.where(workspace: workspace).delete_all
Suppression.where(workspace: workspace, note: "demo_scores.rb").delete_all

# Reset triage state too, so the demo is repeatable: without this, every lead
# decided during a previous walkthrough stays decided and the queue slowly
# empties. Safe here because this file refuses to run outside development.
ReviewDecision.where(workspace: workspace).delete_all
workspace.leads.update_all(status: "new", snoozed_until: nil)
puts "cleared #{cleared} score(s) and reset triage state"

RATIONALES = [
  "Hiring multiple backend engineers shortly after a funding announcement, and the stack matches ours closely.",
  "Small team scaling fast with no in-house platform expertise — a plausible fit for an outside build.",
  "Clear Rails signal in the posting and a named engineering lead to approach.",
  "Product company rather than an agency, hiring for a build rather than maintenance.",
  "Remote-friendly and hiring senior, which usually means budget is already approved.",
  "Strong stack fit but the team already looks large enough to build this in-house.",
  "Evidence is thin — the post gives a name and little else, so confidence is low."
].freeze

def dimensions_for(total)
  base = (total / 10.0).round
  {
    "fit" => base.clamp(0, 10),
    "timing" => (base + 1).clamp(0, 10),
    "reachability" => (base - 1).clamp(0, 10)
  }
end

def score!(lead, icp, total:, flagged: false, rationale: nil)
  evidence_ids = lead.company.evidences.order(:id).pluck(:id)
  cited = flagged ? [ 999_999_999 ] : evidence_ids.first(3)

  Score.create!(
    workspace: lead.workspace,
    lead: lead,
    icp_definition: icp,
    total: total,
    dimensions: dimensions_for(total),
    rationale: rationale || RATIONALES.sample,
    cited_evidence_ids: cited,
    confidence: (total / 120.0).round(2),
    model: AnthropicClient.model,
    flagged_reason: flagged ? Scoring::EvidenceValidator.new(lead: lead, cited_ids: cited).failure_reason : nil
  )
end

srand(20260918) # deterministic across runs

# Prefer leads whose company has a domain: they render better and they are the
# ones a suppression can actually match.
candidates = workspace.leads
  .joins(:company)
  .where.not(companies: { domain: nil })
  .order(:id)
  .to_a
candidates += (workspace.leads.order(:id).to_a - candidates)
abort "No leads to score — run the pipeline first" if candidates.size < 30

queued     = candidates.shift(26) # > ReviewQueue::CAP, so the cap is exercised
below      = candidates.shift(4)
flagged    = candidates.shift(1).first
rescored   = candidates.shift(1).first
snoozed    = candidates.shift(1).first
decided    = candidates.shift(1).first
suppressed = candidates.shift(1).first

# 26 leads above the threshold, spread across the range so ordering is visible.
queued.each_with_index do |lead, i|
  score!(lead, icp, total: 96 - (i * 2))
end

below.each_with_index { |lead, i| score!(lead, icp, total: 34 - (i * 6)) }

score!(flagged, icp, total: 93, flagged: true,
  rationale: "Looks outstanding on every axis — which is exactly why the citation check matters.")

# Older flagged score, then a newer clean one. The queue must judge the lead on
# the newer score and let it through; the id tiebreaker settles same-timestamp rows.
score!(rescored, icp, total: 88, flagged: true)
score!(rescored, icp, total: 71, rationale: "Re-scored under the same rubric after the first attempt cited an id that does not exist.")

score!(snoozed, icp, total: 84)
snoozed.update!(snoozed_until: 30.days.from_now)

score!(decided, icp, total: 82)
decided.update!(status: "qualified")

score!(suppressed, icp, total: 90)
workspace.suppressions.create!(
  domain: suppressed.company.domain, reason: "current_client", note: "demo_scores.rb"
)

queue = ReviewQueue.new(workspace: workspace).leads

puts <<~SUMMARY

  Seeded #{Score.where(workspace: workspace).count} scores across #{Score.where(workspace: workspace).select(:lead_id).distinct.count} leads.

  Review queue: #{queue.size} leads (cap #{ReviewQueue::CAP}, threshold #{ReviewQueue::THRESHOLD})
  Top of queue: #{queue.first(3).map { |l| "#{l.company.name} #{l.latest_score.total}" }.join(' | ')}

  Deliberately excluded, each demonstrating one rule:
    #{below.size} leads scored below #{ReviewQueue::THRESHOLD}
    "#{flagged.company.name}" — score 93 but cites a fabricated evidence id (flagged and withheld)
    "#{snoozed.company.name}" — snoozed until #{snoozed.snoozed_until.to_date}
    "#{decided.company.name}" — already qualified, so no longer "new"
    "#{suppressed.company.name}" — domain #{suppressed.company.domain} is suppressed as a current client

  Included on purpose:
    "#{rescored.company.name}" — an older flagged score, superseded by a clean one

  Open http://localhost:3000/review and use j/k to move, a/d/s to decide.
SUMMARY
