# Leads Pipeline — Design

**Date:** 2026-09-18
**Status:** Approved, pending implementation planning
**Scope of this document:** the whole system. The first implementation plan covers Milestones 1–2 only.

---

## 1. Problem

A one-person software development consultancy has an empty top of funnel. The bottleneck is
not qualification, timing, or follow-up discipline — it is that there is no reliable stream of
plausible prospects at all.

The tool is built first as a personal tool, with an eventual path to SaaS for freelancers and
small-to-medium agencies. That second audience shapes some decisions now (workspace-scoped
schema, data provenance) but no SaaS feature is built in any milestone described here.

### What is being sold

Four offerings, in rough order of preference: specialist niche work, MVP/product builds,
rescue and modernisation of legacy systems, and staff augmentation. The ICP is therefore
genuinely plural, not yet narrowed.

This is a real constraint, not a detail to resolve later. Signal-based sourcing needs a
hypothesis to target, and a single fixed ICP would be a guess. The design responds by making
**ICP a first-class, versioned, multiply-instantiable object** and by building a feedback loop
that measures which ICP actually converts. ICP discovery is treated as a product feature, not
a prerequisite.

### Markets

UK, EU/EEA, US, and market-agnostic remote work. Two consequences:

- The first adapter must be geography-agnostic. National registries (Companies House, SEC
  Form D) are optional add-ons, never the foundation.
- **GDPR applies.** Provenance and suppression are requirements, not hygiene.

---

## 2. Competitive landscape

The market is unbundled into layers, and no product owns the whole loop for a services seller.

| Layer | Representative players | Entry price |
|---|---|---|
| Contact data | Apollo, ZoomInfo, Cognism, Lusha | Apollo ~$49–59/user/mo |
| Enrichment / orchestration | **Clay**, Ocean.io, Keyplay | Clay Launch $185/mo |
| Sending / deliverability | Instantly, Smartlead, lemlist | ~$37/mo+ |
| LinkedIn automation | Expandi, Dripify, HeyReach, PhantomBuster | $50–100/mo |
| Bundled AI SDR | AiSDR, Salesforge, 11x, Artisan | $300–1000+/mo |
| CRM | HubSpot, Pipedrive, Attio, Folk | varies |
| Signal intelligence | Bounce Watch, Recruit Signals, Common Room | unsettled |

Four findings drive the design:

1. **The signal layer is where consultancies win.** Hiring triggers, funding rounds, tech-stack
   changes, leadership hires, and rebrands outperform cold lists. Timing windows are narrow:
   funding is most actionable within a week, a new CTO within a month, and 60–90 days
   post-funding is the window before vendor relationships lock in.
2. **Every incumbent optimises for volume outbound.** A consultancy needs roughly twenty
   well-researched conversations a quarter, not five thousand emails a month. That inverts the
   design target toward deep research per lead.
3. **LinkedIn is the riskiest available source.** Scraping public data is broadly lawful after
   *hiQ*, but violates LinkedIn's User Agreement; Sales Navigator's SNAP programme forbids lead
   export; LinkedIn sued Proxycurl's parent in January 2025. Account bans are routine.
4. **The bundle is the opening.** Nobody sells signal → scoring → research → outreach →
   pipeline as one loop at solo-operator pricing.

**Positioning.** *We find and research; you send.* Every competitor claims the opposite, and
their customers' sending domains absorb the cost.

---

## 3. Goals and non-goals

### Goals
- Fill an empty top of funnel from multiple pluggable sources
- Score and qualify leads with cited, auditable evidence
- Surface a short, capped daily review queue
- Learn the operator's ICP from their own decisions
- Support outreach drafting and lightweight pipeline tracking
- Run unattended on a schedule without unbounded cost

### Non-goals (all milestones)
- Email sending infrastructure, warming, or deliverability management
- Multi-tenancy, billing, or any SaaS surface
- Workflow automation builders, forecasting, quotes, team assignment, reporting suites
- Autonomous outreach. Every outbound message is drafted and sent by a human.

---

## 4. Architecture

### Stack

As scaffolded: **Rails 8.1.3, Ruby 3.4.5, PostgreSQL**, Solid Queue (jobs, and the scheduler via
`config/recurring.yml`), Solid Cache, Solid Cable, Propshaft, Turbo, Stimulus.

**Deployment target is Fly.io.** The scaffold ships Kamal and a Dockerfile; the Dockerfile is
reused and a `fly.toml` is added. Kamal config is left in place, unused.

Three process groups:

- `web` — Puma
- `worker` — Solid Queue workers and scheduler
- `browser` — **isolated machine, the only process permitted to run Playwright**

The browser machine exists so that ToS-risky scraping has its own blast radius and can be
scaled to zero, killed, or deleted without touching the application.

### Pipeline

A saved **Search**, when executed, produces an immutable **Run**. Hits flow through six stages:

```
 Search (saved ICP + params)
      │  scheduled by Solid Queue
      ▼
 ① DISCOVER   source adapters → RawHit (verbatim payload)
      ▼
 ② NORMALIZE  → Company / Person canonical records
      ▼
 ③ DEDUPE     identity resolution on identifiers + fuzzy name
      ▼
 ④ ENRICH     further adapters, survivors only
      ▼
 ⑤ SCORE      AI, structured output, rubric from the Search
      ▼
 ⑥ QUEUE      → review inbox
      ▼
   operator decision → feedback → ICP refinement
```

**Funnel narrowing is the cost control.** Stage ① may return thousands of cheap hits; stage ⑤
is the only expensive stage and only ever sees dozens. The ordering is load-bearing, not
incidental.

### Principles

**Evidence-first.** No unattributed facts. Every attribute is an `Evidence` record carrying
source, URL, fetched-at, raw payload reference, and the extracted claim. Scores cite evidence
IDs. This makes scores trustworthy enough to act on, makes bad scores debuggable, and answers
the GDPR question "where did you get this".

**Adapters are dumb and uniform.** An adapter implements `search(params) → [RawHit]` plus a
capability manifest declaring accepted params, returned fields, cost per call, and risk level.
Adapters perform no scoring, no dedupe, and no AI calls. Adapter count is the moat, so adapters
must be cheap to add; and a blocked or broken source then fails one stage of one run rather
than corrupting the pipeline.

**Runs are immutable and measured.** Each run records hits found, survivors after dedupe, score
distribution, cost, and eventually conversion. Without run history, "which search actually
works" is unanswerable, and the ICP feedback loop has no input.

---

## 5. Data model

PostgreSQL throughout; `jsonb` where shape is source-dependent. Every table is workspace-scoped.

### Search definition
- `workspaces` — one row initially; exists so SaaS is a schema change, not a rewrite
- `searches` — name, status (`draft`/`active`/`paused`), cron schedule
- `icp_definitions` — **versioned**, belongs to a search: natural-language brief, compiled
  criteria (jsonb), scoring rubric (jsonb), version, active flag
- `search_sources` — join: search × adapter key × adapter params (jsonb) × enabled

### Execution
- `runs` — belongs to search; **pins the `icp_definition` version in force**; stats, timings, status
- `run_source_executions` — per adapter per run: status, hit count, cost, error
- `raw_hits` — belongs to a `run_source_execution`; verbatim payload, source key, source UID,
  fetched-at. **Never mutated.**

### Canonical entities
- `companies` — name, domain, size estimate, location, industry, first-seen-at
- `people` — name, title, company, seniority, contact details
- `company_identifiers` — (kind, value) pairs: domain, LinkedIn slug, Crunchbase ID,
  normalised name. Uniquely indexed per workspace per kind. This is the dedupe mechanism.
- `evidence` — polymorphic: subject, attribute name, value, source key, source URL, fetched-at,
  `raw_hit_id`, confidence
- `signals` — belongs to company: type (funding, hiring burst, leadership hire, rebrand, stack
  change, RFP), occurred-at, detected-at, payload, evidence reference

### Funnel
- `leads` — **one per company per workspace**
- `lead_discoveries` — lead × run × search × discovered-at
- `scores` — **append-only**: lead, `icp_definition` version, model ID, total, dimension
  sub-scores (jsonb), rationale, cited evidence IDs, token cost
- `review_decisions` — lead, decision (`advance`/`disqualify`/`snooze`), **reason code**, note,
  snooze-until, decided-at
- `dossiers` — lead, markdown content, generated-at, model, cited evidence IDs, ICP version
- `pipeline_stages`, `stage_transitions`, `activities`, `tasks`, `outreach_drafts`

### Scout (Milestone 5)
- `scout_runs` — search, prompt, transcript, cost
- `suggestions` — scout run, kind (`new_source`/`new_query`/`icp_refinement`), payload,
  status (`pending`/`accepted`/`rejected`)

### Operations
- `adapter_credentials` — **workspace-scoped and Rails-encrypted, never global ENV**
- `cost_ledger` — every paid API call and model call
- `suppressions` — domain or email, reason (`current_client`/`competitor`/`opted_out`/
  `do_not_contact`)

### Decisions worth defending

1. **`leads` are per-company, not per-search.** Per-search leads flood the inbox with the same
   company several times. One lead plus `lead_discoveries` means "found independently by three
   searches" becomes a quality signal instead of a duplicate.
2. **ICP definitions are versioned and scores pin the version.** Refining an ICP otherwise
   silently makes score history incomparable, which kills the feedback loop.
3. **`scores` are append-only.** Re-scoring inserts. This yields score drift over time and lets
   two rubric versions be diffed over the same lead set — the cheapest possible eval.
4. **`raw_hits` are immutable and retained.** They are a replay buffer: improved normalisation
   re-derives from stored payloads instead of re-fetching, which for paid sources costs money
   again and for LinkedIn may be impossible twice.
5. **`signals` are distinct from `evidence`.** Evidence is a durable claim ("uses Rails"). A
   signal is a dated event that decays ("raised Series B on 3 March"). They score differently —
   signals carry the timing dimension — and only signals drive alerting.
6. **`review_decisions` carry a reason code.** "Too small", "wrong stack", "no budget signal",
   "already a client" aggregates into ICP refinement. Free text does not.

---

## 6. AI layer

Ruby SDK (`anthropic` gem). **`claude-opus-5`** throughout, adaptive thinking
(`thinking: {type: "adaptive"}`). Model and effort are cost levers to be tuned later against
measured quality, deliberately not pre-optimised.

### ① Search compilation
Natural-language brief → structured output producing compiled per-source params and the
scoring rubric. Interactive, low volume, negligible cost. Uses `output_config.format` so the
result validates against schema rather than needing parsing.

### ② Scoring — the volume stage
Structured output returning dimension sub-scores, rationale, cited evidence IDs, and
confidence. Three cost levers, all necessary because this runs unattended:

- **Prompt caching.** Rubric, ICP, and accumulated past decisions form a stable prefix; only
  the lead's evidence varies, and is placed last. Near-100% cache hit rate within a run;
  cached input reads at roughly a tenth of base rate. Verify via
  `usage.cache_read_input_tokens`.
- **Batch API.** Scheduled overnight runs are the textbook non-latency-sensitive workload:
  50% discount.
- **Funnel position.** Scoring sees only post-dedupe survivors.

**Guardrail — evidence citation validator.** Every evidence ID cited by the model is checked
to exist; a score citing a non-existent ID is flagged and withheld. A scoring model that
invents its own justification is the most dangerous failure mode here precisely because the
output looks correct.

### ③ Dossier
`claude-opus-5` with the server-side `web_search` and `web_fetch` tools, run only for leads
above threshold or on demand. Produces the one-page brief read before outreach. Highest cost
per unit, lowest volume.

### ④ Outreach drafting
Dossier plus a cached prefix of the operator's past emails as voice examples.

**Specificity validator:** a draft must cite at least one specific signal or evidence item. A
draft that would read acceptably addressed to any company is rejected — that is the exact
failure mode that makes AI outreach detectable.

Both the generated version and the version actually sent are stored. The diff between them is
the voice-training data, obtained free.

### ⑤ Scout — contained agentic sourcing (Milestone 5)
Ruby tool runner (`Anthropic::BaseTool` + `client.beta.messages.tool_runner`) with web search,
web fetch, and one custom `propose_suggestion` tool. Two hard constraints:

- It writes **only** to `suggestions`, never to `leads`
- It runs under a **task budget** (`output_config.task_budget`) so it paces itself toward a
  token ceiling rather than being cut off mid-task

Manual trigger only. These constraints are what prevent open-ended agentic sourcing from
becoming an unbounded bill or a queue of plausible-looking fabricated companies.

### Feedback loop
`review_decisions` with reason codes accumulate into the cached few-shot prefix for scoring, so
the system learns the operator's taste with no fine-tuning. Periodically a refinement call reads
aggregated decisions and proposes rubric changes as `suggestions` requiring approval.

**This is the differentiating feature.** Clay and Apollo require indefinite manual filter tuning.

### Estimated running cost, personal volume

At ~200 leads scored per week, ~20 dossiers and ~20 drafts per month:

| Stage | Estimated monthly |
|---|---|
| Scoring (cached + batched) | $12–25 |
| Dossiers | $5–10 |
| Drafts and compilation | ~$2 |
| Scout (budgeted, occasional) | ~$5 |
| **Total** | **~$25–45** |

Estimates, not quotes. `cost_ledger` records actuals from Milestone 2 onward. For comparison,
Clay's entry plan is $185/month.

---

## 7. Review loop

### Queue assembly

The queue is **not** "new leads sorted by score" — that version is abandoned by week three. It
is a unified daily surface assembled from four sources:

1. New leads above threshold
2. Snoozed leads now due
3. Existing leads with a **fresh signal**, resurfaced regardless of prior decision
4. **Stalled leads** — in a stage beyond its threshold with no activity

Source 4 solves follow-up discipline with a scheduled query rather than a workflow builder.

**The queue is hard-capped at 20 items.** An unbounded queue is an ignored queue. Anything below
threshold lives in the table view and does not compete for the operator's morning.

**Snooze is a first-class verb with a date and a reason code.** In consulting sales "not now" is
the most common truthful answer, and most CRMs force a lie — disqualify, or leave open to rot.

### Interface: keyboard-driven triage inbox

Dense list left, detail pane right. Full keyboard operation: `j`/`k` to move, `a` advance,
`d` disqualify, `s` snooze. The detail pane shows score dimensions, rationale, and evidence,
expandable to the full dossier. Turbo Streams keep it live; Stimulus owns the key bindings.

A dense sortable table exists as a **secondary view** for auditing whether a search is working
and for bulk disqualification. It is explicitly not the daily surface: it shows a number and
hides the reasoning, which reintroduces volume thinking.

---

## 8. CRM and outreach

### Deliberately thin

CRM is an infinite surface and the operator is one person. **Built:** configurable ordered
stages (Researching → Contacted → In conversation → Proposal → Won/Lost), `stage_transitions`
for cycle time and stall detection, a polymorphic activity timeline, tasks with due dates,
notes. The stall detector is the only automation, and it is a scheduled query.

### Email: draft here, send from your own mailbox

**No sending infrastructure is built, in any milestone.** Deliverability is an entire industry.
More importantly, sending from a personal mailbox is better for a consultancy: higher
deliverability, and a real person rather than a sequence.

- **Milestone 4:** the app drafts; the operator copies into their mail client; a **BCC dropbox
  address** parses the message and files it against the lead. No OAuth, no deliverability
  ownership.
- **Later, if the BCC habit proves annoying:** Gmail/IMAP read-only sync for full thread capture.

### Suppression and compliance

Suppressions are checked **before anything surfaces** — current clients, competitors, opted-out,
recently contacted.

GDPR: B2B outreach in the EU/UK runs on legitimate interest, requiring demonstrable data
provenance and honoured opt-outs. The `evidence` table supplies provenance and `suppressions`
supplies opt-out, so compliance is nearly free **provided both are kept from the start**.
Retrofitting provenance onto a system that discarded its sources is a rewrite, and would block
any SaaS launch.

---

## 9. Search builder

**Brief → compiled spec, visible and editable.**

The operator writes a paragraph describing the target. The AI compiles it into a structured
spec: criteria chips, enabled sources with per-source params, and rubric weights — all
editable. The brief is retained as the statement of intent; the compiled spec is the artifact.

The AI explicitly flags where it had to approximate an unobservable criterion (for example,
"no agency of record" approximated as "no agency backlink on the site").

Each edit produces a new `icp_definition` version, so two versions can be diffed and their
score distributions compared.

**Rejected alternatives:**

- *Conversational interview.* Lowest barrier, but the saved search is opaque, cannot be diffed,
  and editing means re-negotiating in chat. Cut entirely.
- *Dry run and teach-by-example.* Rough brief → sample results → thumbs up/down → AI infers the
  rule. Genuinely valuable, and shares machinery with the review loop. **Deferred to Milestone 5**,
  where that machinery already exists and a credit-free sample path can be built properly.

---

## 10. Milestones

### M1 — Walking skeleton: one search, one source, end to end
Postgres schema for the core pipeline. Search created by hand, no AI. **One adapter: Hacker
News "Who is Hiring"** via the free Algolia API — geography-agnostic, parseable, and dense with
funded startups actively seeking developers. Pipeline stages ①–④. Evidence records. Plain list
view. Deployed to Fly.io.

*Rationale:* proves the pipeline and the adapter abstraction against a real source at zero cost
and zero risk. If the abstraction is wrong, that surfaces in week one rather than after five
adapters exist.

### M2 — Scoring and the triage inbox
AI scoring: structured output, cached rubric prefix, batch execution, evidence citation
validator. Keyboard triage queue. Review decisions with reason codes. Cost ledger.
Suppressions.

**At the end of M2 the tool is useful.** Everything after is leverage.

### M3 — Always-on
Brief → compiled spec builder. Solid Queue recurring schedules. Two or three further adapters
(funding news, job aggregators, tech-stack detection). Full four-source queue assembly.

### M4 — Conversation
Dossiers with web search. Outreach drafts with the specificity validator. BCC dropbox. Thin
CRM: stages, transitions, stall detection, activities, tasks.

### M5 — The loop closes
ICP refinement from aggregated decisions. Dry-run teach-by-example. Scout agent under a task
budget.

### Deferred

**LinkedIn is built last, and that is a recommendation rather than mere sequencing.** The
operator has accepted the risk, which is their decision. But by M5 it will be known whether free
and paid sources already fill the funnel. If they do, the risk is never taken; if they do not,
one isolated adapter is added on the `browser` machine with full knowledge of what it buys.
Building it first would mean accepting legal and account risk before establishing need.

Also deferred indefinitely: multi-tenancy, billing, email sending, mobile.

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| Plural ICP makes targeting diffuse | Multiple named searches; feedback loop measures which converts |
| Scoring model fabricates justification | Evidence citation validator rejects scores citing unknown IDs |
| Always-on costs run away | Funnel narrowing, prompt caching, Batch API, cost ledger, task budgets on the scout |
| Free sources are thin or break | Adapters are isolated; one failure degrades one run stage |
| LinkedIn account ban or legal action | Isolated adapter on a separate machine, built last, never a dependency |
| GDPR exposure | Provenance from day one; suppressions checked before surfacing |
| CRM scope creep | Explicit non-goals; stall detection is the only automation |
| Review queue abandoned | Hard 20-item cap; keyboard-first; snooze as a first-class verb |

---

## 12. Decisions deferred to implementation

These are deliberately unresolved, with a stated default so no milestone is blocked:

- **Paid enrichment provider** (contact details). Default: none until M3; evaluate then against
  the funnel's actual gap.
- **Score thresholds** for queue entry and dossier generation. Default: set empirically during
  M2 from the first observed score distribution; not guessed in advance.
- **Postgres hosting.** Default: Fly Postgres, revisited only if operational burden warrants.
- **Stall thresholds** per stage. Default: 14 days, configurable per stage from M4.
