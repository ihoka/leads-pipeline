# Leads Pipeline — Milestones 1 & 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working lead sourcing pipeline that discovers companies from Hacker News "Who is Hiring", resolves them to canonical records with full provenance, scores them with Claude against a versioned ICP, and presents them in a keyboard-driven daily triage inbox.

**Architecture:** A deterministic six-stage pipeline (discover → normalize → dedupe → enrich → score → queue) driven by Solid Queue. Source adapters are uniform and dumb: they return verbatim payloads and nothing else. Every attribute on a company carries an `Evidence` record pointing back to the raw payload it came from, and AI scores must cite evidence IDs that are validated to exist.

**Tech Stack:** Rails 8.1.3, Ruby 3.4.5, PostgreSQL, Solid Queue, Turbo, Stimulus, Propshaft, Minitest, WebMock, `anthropic` gem 1.71, deployed to Fly.io.

**Spec:** `docs/superpowers/specs/2026-09-18-leads-pipeline-design.md`

## Global Constraints

- Ruby 3.4.5, Rails 8.1.3 (already scaffolded — do not upgrade)
- PostgreSQL only. Solid Queue/Cache/Cable use their own databases per the scaffold's `config/database.yml`
- Minitest, not RSpec. WebMock for all external HTTP. **No test may make a real network call.**
- Claude model is `claude-opus-5` with `thinking: {type: "adaptive"}`. Never substitute a cheaper model.
- **Every table is workspace-scoped.** Every model has `belongs_to :workspace` (directly or through a parent).
- **No attribute without provenance.** Any company or person attribute derived from a source must have a corresponding `Evidence` row.
- `scores` is append-only. Never `update` a score; always insert a new one.
- `raw_hits` are immutable. Never update or delete them.
- No email sending code in any task.
- Ruby SDK gotchas, verified against gem 1.71.0 source: the system prompt parameter is **`system_`** (trailing underscore) and the structured-output field is **`format_`** (trailing underscore, serialised to `format`).
- **Creating migrations:** every migration in this plan is created with `bin/rails generate migration <ClassName>` and then its generated body replaced wholesale with the code given in the step. The generated timestamp prefix is whatever Rails assigns; only the class name must match.

## Deviation from the spec: batch scoring

The spec's Milestone 2 calls for scoring via the Batch API at 50% cost. **This plan uses synchronous `messages.create` instead**, and defers batching to Milestone 3.

The reasoning: batching introduces async submission, polling, and result-reconciliation against a job that must also handle partial failure — a meaningful amount of machinery. At M2 volume (one HN thread yields a few hundred posts, of which a minority parse into companies) the saving is a few dollars a month, and the synchronous path is far easier to get correct and to test. Batching becomes worth its complexity at M3, when several adapters run nightly against a much larger candidate set.

The cost lever that *does* apply immediately — prompt caching — is implemented in Task 11, and it is the larger of the two savings at this volume.

This is a deliberate, recorded deviation, not an omission. Revisit it in the M3 plan.

---

## File Structure

| Path | Responsibility |
|---|---|
| `app/models/workspace.rb` | Tenancy root |
| `app/models/search.rb`, `icp_definition.rb` | Saved search + versioned ICP |
| `app/models/company.rb`, `company_identifier.rb`, `person.rb` | Canonical entities |
| `app/models/evidence.rb` | Provenance for every claim |
| `app/models/run.rb`, `run_source_execution.rb`, `raw_hit.rb` | Immutable execution history |
| `app/models/lead.rb`, `lead_discovery.rb` | The funnel |
| `app/models/score.rb`, `review_decision.rb` | Scoring + operator feedback |
| `app/models/suppression.rb`, `cost_ledger_entry.rb` | Compliance + spend |
| `app/services/sources/adapter.rb` | Adapter contract |
| `app/services/sources/hit.rb` | Value object returned by adapters |
| `app/services/sources/registry.rb` | Adapter lookup by key |
| `app/services/sources/hacker_news_who_is_hiring.rb` | The M1 adapter |
| `app/services/normalizers/hacker_news_post.rb` | RawHit → company attrs + evidence |
| `app/services/identity_resolver.rb` | Dedupe / merge on identifiers |
| `app/services/scoring/scorer.rb` | Claude scoring call |
| `app/services/scoring/evidence_validator.rb` | Rejects fabricated citations |
| `app/services/scoring/rubric_prompt.rb` | Builds the cacheable prompt prefix |
| `app/services/anthropic_client.rb` | Configured SDK client |
| `app/services/review_queue.rb` | Assembles the capped daily queue |
| `app/jobs/run_search_job.rb` | Orchestrator |
| `app/jobs/discover_job.rb`, `normalize_job.rb`, `score_lead_job.rb` | Pipeline stages |
| `app/controllers/leads_controller.rb`, `review_controller.rb` | UI |
| `app/javascript/controllers/triage_controller.js` | Keyboard navigation |

---

# MILESTONE 1 — Walking skeleton

---

### Task 1: Foundation — workspace, search, versioned ICP

**Files:**
- Create: `db/migrate/*_create_workspaces.rb`, `*_create_searches.rb`, `*_create_icp_definitions.rb`
- Create: `app/models/workspace.rb`, `app/models/search.rb`, `app/models/icp_definition.rb`
- Modify: `Gemfile`
- Test: `test/models/icp_definition_test.rb`, `test/models/search_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces: `Workspace`, `Search`, `IcpDefinition`. `Search#active_icp_definition → IcpDefinition | nil`. `IcpDefinition#version → Integer` (auto-assigned, 1-based, per search).

- [ ] **Step 1: Add test and dev gems**

Add to `Gemfile` inside the existing `group :development, :test do` block:

```ruby
  gem "webmock", "~> 3.26", require: false
```

Add at top level (outside any group):

```ruby
# Claude API client for scoring, dossiers, and drafting
gem "anthropic", "~> 1.71"
```

Then run:

```bash
bundle install
bin/rails db:create
```

- [ ] **Step 2: Enable WebMock globally in tests**

Modify `test/test_helper.rb` — add after the existing requires:

```ruby
require "webmock/minitest"
WebMock.disable_net_connect!(allow_localhost: true)
```

- [ ] **Step 3: Write the failing tests**

Create `test/models/icp_definition_test.rb`:

```ruby
require "test_helper"

class IcpDefinitionTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @search = @workspace.searches.create!(name: "Funded & Rails-shaped")
  end

  test "assigns sequential versions per search" do
    first = @search.icp_definitions.create!(brief: "v1 brief")
    second = @search.icp_definitions.create!(brief: "v2 brief")

    assert_equal 1, first.version
    assert_equal 2, second.version
  end

  test "versions are independent across searches" do
    other = @workspace.searches.create!(name: "Legacy rescue")
    @search.icp_definitions.create!(brief: "a")
    fresh = other.icp_definitions.create!(brief: "b")

    assert_equal 1, fresh.version
  end

  test "only the newest definition is active" do
    old = @search.icp_definitions.create!(brief: "old")
    new = @search.icp_definitions.create!(brief: "new")

    assert_equal new, @search.reload.active_icp_definition
    refute_equal old, @search.active_icp_definition
  end

  test "requires a brief" do
    definition = @search.icp_definitions.build(brief: "")
    refute definition.valid?
  end

  test "defaults criteria and rubric to empty hashes" do
    definition = @search.icp_definitions.create!(brief: "x")

    assert_equal({}, definition.compiled_criteria)
    assert_equal({}, definition.scoring_rubric)
  end
end
```

Create `test/models/search_test.rb`:

```ruby
require "test_helper"

class SearchTest < ActiveSupport::TestCase
  setup { @workspace = Workspace.create!(name: "Personal") }

  test "requires a name" do
    refute @workspace.searches.build(name: "").valid?
  end

  test "defaults to draft status" do
    assert_equal "draft", @workspace.searches.create!(name: "X").status
  end

  test "active scope returns only active searches" do
    active = @workspace.searches.create!(name: "A", status: "active")
    @workspace.searches.create!(name: "B", status: "paused")

    assert_equal [ active ], Search.active.to_a
  end
end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bin/rails test test/models/`
Expected: FAIL — `NameError: uninitialized constant Workspace`

- [ ] **Step 5: Create migrations**

```bash
bin/rails generate migration CreateWorkspaces name:string
bin/rails generate migration CreateSearches
bin/rails generate migration CreateIcpDefinitions
```

Replace the body of the workspaces migration:

```ruby
class CreateWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces do |t|
      t.string :name, null: false
      t.timestamps
    end
  end
end
```

Searches migration:

```ruby
class CreateSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :searches do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.string :schedule
      t.timestamps
    end
    add_index :searches, [ :workspace_id, :status ]
  end
end
```

ICP definitions migration:

```ruby
class CreateIcpDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :icp_definitions do |t|
      t.references :search, null: false, foreign_key: true
      t.integer :version, null: false
      t.text :brief, null: false
      t.jsonb :compiled_criteria, null: false, default: {}
      t.jsonb :scoring_rubric, null: false, default: {}
      t.timestamps
    end
    add_index :icp_definitions, [ :search_id, :version ], unique: true
  end
end
```

- [ ] **Step 6: Write the models**

`app/models/workspace.rb`:

```ruby
class Workspace < ApplicationRecord
  has_many :searches, dependent: :destroy

  validates :name, presence: true
end
```

`app/models/search.rb`:

```ruby
class Search < ApplicationRecord
  STATUSES = %w[draft active paused].freeze

  belongs_to :workspace
  has_many :icp_definitions, -> { order(version: :desc) }, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def active_icp_definition
    icp_definitions.first
  end
end
```

`app/models/icp_definition.rb`:

```ruby
class IcpDefinition < ApplicationRecord
  belongs_to :search

  validates :brief, presence: true
  validates :version, presence: true, uniqueness: { scope: :search_id }

  before_validation :assign_version, on: :create

  private
    def assign_version
      self.version ||= (search.icp_definitions.maximum(:version) || 0) + 1
    end
end
```

- [ ] **Step 7: Migrate and run tests**

Run: `bin/rails db:migrate && bin/rails test test/models/`
Expected: PASS — 8 runs, 0 failures

- [ ] **Step 8: Commit**

```bash
git add Gemfile Gemfile.lock test/test_helper.rb db/ app/models/ test/models/
git commit -m "Add workspace, search, and versioned ICP definition models

ICP definitions are versioned per search so that scores can pin the
version they were produced under, keeping score history comparable
across ICP refinements."
```

---

### Task 2: Canonical entities and identity resolution

**Files:**
- Create: `db/migrate/*_create_companies.rb`, `*_create_company_identifiers.rb`, `*_create_people.rb`, `*_create_evidences.rb`
- Create: `app/models/company.rb`, `company_identifier.rb`, `person.rb`, `evidence.rb`
- Create: `app/services/identity_resolver.rb`
- Test: `test/services/identity_resolver_test.rb`, `test/models/evidence_test.rb`

**Interfaces:**
- Consumes: `Workspace` (Task 1)
- Produces:
  - `IdentityResolver.new(workspace:).resolve(identifiers:, attrs:) → Company`
    where `identifiers` is `[{kind: "domain", value: "acme.com"}, ...]` and `attrs` is a Hash of company columns.
  - `CompanyIdentifier::KINDS = %w[domain linkedin_slug crunchbase_id normalized_name]`
  - `Evidence` columns: `subject` (polymorphic), `attribute_name`, `value`, `source_key`, `source_url`, `fetched_at`, `raw_hit_id`, `confidence`

- [ ] **Step 1: Write the failing tests**

Create `test/services/identity_resolver_test.rb`:

```ruby
require "test_helper"

class IdentityResolverTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @resolver = IdentityResolver.new(workspace: @workspace)
  end

  test "creates a company when no identifier matches" do
    company = @resolver.resolve(
      identifiers: [ { kind: "domain", value: "acme.com" } ],
      attrs: { name: "Acme" }
    )

    assert company.persisted?
    assert_equal "Acme", company.name
    assert_equal 1, Company.count
  end

  test "returns the existing company when an identifier matches" do
    first = @resolver.resolve(identifiers: [ { kind: "domain", value: "acme.com" } ], attrs: { name: "Acme" })
    second = @resolver.resolve(identifiers: [ { kind: "domain", value: "acme.com" } ], attrs: { name: "Acme Corp" })

    assert_equal first.id, second.id
    assert_equal 1, Company.count
  end

  test "matches on any one of several identifiers" do
    first = @resolver.resolve(
      identifiers: [ { kind: "domain", value: "acme.com" }, { kind: "normalized_name", value: "acme" } ],
      attrs: { name: "Acme" }
    )
    second = @resolver.resolve(
      identifiers: [ { kind: "normalized_name", value: "acme" } ],
      attrs: { name: "Acme" }
    )

    assert_equal first.id, second.id
  end

  test "attaches new identifiers to an already-resolved company" do
    @resolver.resolve(identifiers: [ { kind: "domain", value: "acme.com" } ], attrs: { name: "Acme" })
    company = @resolver.resolve(
      identifiers: [ { kind: "domain", value: "acme.com" }, { kind: "linkedin_slug", value: "acme-inc" } ],
      attrs: {}
    )

    assert_equal %w[domain linkedin_slug], company.company_identifiers.order(:kind).pluck(:kind)
  end

  test "does not fill an attribute that is already set" do
    @resolver.resolve(identifiers: [ { kind: "domain", value: "acme.com" } ], attrs: { name: "Acme" })
    company = @resolver.resolve(identifiers: [ { kind: "domain", value: "acme.com" } ], attrs: { name: "Acme Corp" })

    assert_equal "Acme", company.name
  end

  test "fills an attribute that was previously blank" do
    @resolver.resolve(identifiers: [ { kind: "domain", value: "acme.com" } ], attrs: { name: "Acme" })
    company = @resolver.resolve(
      identifiers: [ { kind: "domain", value: "acme.com" } ],
      attrs: { location: "Bristol, UK" }
    )

    assert_equal "Bristol, UK", company.location
  end

  test "isolates companies across workspaces" do
    other = Workspace.create!(name: "Other")
    @resolver.resolve(identifiers: [ { kind: "domain", value: "acme.com" } ], attrs: { name: "Acme" })
    IdentityResolver.new(workspace: other).resolve(
      identifiers: [ { kind: "domain", value: "acme.com" } ], attrs: { name: "Acme" }
    )

    assert_equal 2, Company.count
  end

  test "raises on an unknown identifier kind" do
    assert_raises(ArgumentError) do
      @resolver.resolve(identifiers: [ { kind: "nonsense", value: "x" } ], attrs: {})
    end
  end
end
```

Create `test/models/evidence_test.rb`:

```ruby
require "test_helper"

class EvidenceTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @company = @workspace.companies.create!(name: "Acme")
  end

  test "records provenance for a company attribute" do
    evidence = @company.evidences.create!(
      workspace: @workspace,
      attribute_name: "location",
      value: "Bristol, UK",
      source_key: "hn_who_is_hiring",
      source_url: "https://news.ycombinator.com/item?id=1",
      fetched_at: Time.current
    )

    assert evidence.persisted?
    assert_equal @company, evidence.subject
  end

  test "requires a source key" do
    evidence = @company.evidences.build(
      workspace: @workspace, attribute_name: "location", value: "x", fetched_at: Time.current
    )
    refute evidence.valid?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/identity_resolver_test.rb test/models/evidence_test.rb`
Expected: FAIL — `NameError: uninitialized constant IdentityResolver`

- [ ] **Step 3: Create migrations**

```bash
bin/rails generate migration CreateCompanies
bin/rails generate migration CreateCompanyIdentifiers
bin/rails generate migration CreatePeople
bin/rails generate migration CreateEvidences
```

```ruby
class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name
      t.string :domain
      t.string :location
      t.string :industry
      t.integer :size_estimate
      t.datetime :first_seen_at
      t.timestamps
    end
  end
end
```

```ruby
class CreateCompanyIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :company_identifiers do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :value, null: false
      t.timestamps
    end
    add_index :company_identifiers, [ :workspace_id, :kind, :value ], unique: true,
              name: "index_company_identifiers_uniqueness"
  end
end
```

```ruby
class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :company, foreign_key: true
      t.string :name
      t.string :title
      t.string :email
      t.string :linkedin_url
      t.string :seniority
      t.timestamps
    end
  end
end
```

```ruby
class CreateEvidences < ActiveRecord::Migration[8.1]
  def change
    create_table :evidences do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :subject, null: false, polymorphic: true
      t.references :raw_hit, foreign_key: true, null: true
      t.string :attribute_name, null: false
      t.text :value
      t.string :source_key, null: false
      t.string :source_url
      t.datetime :fetched_at, null: false
      t.float :confidence
      t.timestamps
    end
    add_index :evidences, [ :subject_type, :subject_id, :attribute_name ],
              name: "index_evidences_on_subject_and_attribute"
  end
end
```

Note: `raw_hits` does not exist yet (Task 3). Add the foreign key in Task 3 instead — for now change that line to:

```ruby
      t.bigint :raw_hit_id
```

and add `add_index :evidences, :raw_hit_id`.

- [ ] **Step 4: Write the models**

`app/models/company.rb`:

```ruby
class Company < ApplicationRecord
  belongs_to :workspace
  has_many :company_identifiers, dependent: :destroy
  has_many :people, dependent: :nullify
  has_many :evidences, as: :subject, dependent: :destroy

  before_create { self.first_seen_at ||= Time.current }
end
```

`app/models/company_identifier.rb`:

```ruby
class CompanyIdentifier < ApplicationRecord
  KINDS = %w[domain linkedin_slug crunchbase_id normalized_name].freeze

  belongs_to :workspace
  belongs_to :company

  validates :kind, inclusion: { in: KINDS }
  validates :value, presence: true
  validates :value, uniqueness: { scope: [ :workspace_id, :kind ] }
end
```

`app/models/person.rb`:

```ruby
class Person < ApplicationRecord
  belongs_to :workspace
  belongs_to :company, optional: true
  has_many :evidences, as: :subject, dependent: :destroy
end
```

`app/models/evidence.rb`:

```ruby
class Evidence < ApplicationRecord
  belongs_to :workspace
  belongs_to :subject, polymorphic: true
  belongs_to :raw_hit, optional: true

  validates :attribute_name, presence: true
  validates :source_key, presence: true
  validates :fetched_at, presence: true
end
```

Add to `app/models/workspace.rb`:

```ruby
  has_many :companies, dependent: :destroy
  has_many :people, dependent: :destroy
  has_many :evidences, dependent: :destroy
```

- [ ] **Step 5: Write the identity resolver**

`app/services/identity_resolver.rb`:

```ruby
# Resolves a set of source-provided identifiers to a single canonical Company,
# creating one if nothing matches. This is pipeline stage 3 (dedupe).
#
# Attribute filling is deliberately non-destructive: an existing value is never
# overwritten by a later source, because we cannot rank source trustworthiness
# yet and silently changing a resolved company is worse than a stale field.
class IdentityResolver
  def initialize(workspace:)
    @workspace = workspace
  end

  def resolve(identifiers:, attrs: {})
    validate_kinds!(identifiers)

    company = find_by_identifiers(identifiers) || @workspace.companies.create!
    fill_blank_attributes(company, attrs)
    attach_identifiers(company, identifiers)
    company
  end

  private
    def validate_kinds!(identifiers)
      identifiers.each do |identifier|
        unless CompanyIdentifier::KINDS.include?(identifier[:kind].to_s)
          raise ArgumentError, "unknown identifier kind: #{identifier[:kind]}"
        end
      end
    end

    def find_by_identifiers(identifiers)
      return nil if identifiers.empty?

      conditions = identifiers.map { |i| [ i[:kind].to_s, i[:value] ] }
      CompanyIdentifier
        .where(workspace: @workspace)
        .where("(kind, value) IN (?)", conditions)
        .first
        &.company
    end

    def fill_blank_attributes(company, attrs)
      updates = attrs.reject { |key, value| value.blank? || company.read_attribute(key).present? }
      company.update!(updates) if updates.any?
    end

    def attach_identifiers(company, identifiers)
      identifiers.each do |identifier|
        CompanyIdentifier.find_or_create_by!(
          workspace: @workspace, kind: identifier[:kind].to_s, value: identifier[:value]
        ) { |record| record.company = company }
      end
    end
end
```

- [ ] **Step 6: Run tests**

Run: `bin/rails db:migrate && bin/rails test test/services/identity_resolver_test.rb test/models/evidence_test.rb`
Expected: PASS — 10 runs, 0 failures

- [ ] **Step 7: Commit**

```bash
git add db/ app/models/ app/services/ test/
git commit -m "Add canonical entities, evidence provenance, and identity resolution

Identity resolution matches on any one of several identifier kinds, so a
company found by domain in one source and by normalised name in another
resolves to a single record. Attribute filling is non-destructive."
```

---

### Task 3: Run tracking and raw hits

**Files:**
- Create: `db/migrate/*_create_runs.rb`, `*_create_run_source_executions.rb`, `*_create_raw_hits.rb`, `*_add_raw_hit_fk_to_evidences.rb`
- Create: `app/models/run.rb`, `run_source_execution.rb`, `raw_hit.rb`
- Test: `test/models/run_test.rb`

**Interfaces:**
- Consumes: `Search`, `IcpDefinition` (Task 1), `Evidence` (Task 2)
- Produces:
  - `Run` with `status` in `%w[pending running completed failed]`, `stats` jsonb, `icp_definition_id`
  - `Run#record_stats!(key, value)` — increments an integer counter in `stats`
  - `RunSourceExecution` with `status`, `hits_count`, `cost_cents`, `error_message`
  - `RawHit` with `source_key`, `source_uid`, `payload` jsonb, `fetched_at`; **immutable after create**

- [ ] **Step 1: Write the failing test**

Create `test/models/run_test.rb`:

```ruby
require "test_helper"

class RunTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @search = @workspace.searches.create!(name: "HN")
    @icp = @search.icp_definitions.create!(brief: "b")
    @run = @search.runs.create!(workspace: @workspace, icp_definition: @icp)
  end

  test "starts pending and pins the icp definition" do
    assert_equal "pending", @run.status
    assert_equal @icp, @run.icp_definition
  end

  test "record_stats! increments a counter" do
    @run.record_stats!(:hits_found, 3)
    @run.record_stats!(:hits_found, 2)

    assert_equal 5, @run.reload.stats["hits_found"]
  end

  test "raw hits are immutable after create" do
    execution = @run.run_source_executions.create!(workspace: @workspace, source_key: "hn_who_is_hiring")
    hit = execution.raw_hits.create!(
      workspace: @workspace, source_key: "hn_who_is_hiring", source_uid: "1",
      payload: { "a" => 1 }, fetched_at: Time.current
    )

    assert_raises(ActiveRecord::ReadOnlyRecord) { hit.update!(source_uid: "2") }
  end

  test "source executions record failure without failing the run" do
    execution = @run.run_source_executions.create!(workspace: @workspace, source_key: "broken")
    execution.update!(status: "failed", error_message: "timeout")

    assert_equal "failed", execution.status
    assert_equal "pending", @run.reload.status
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/run_test.rb`
Expected: FAIL — `NameError: uninitialized constant Search::Run`

- [ ] **Step 3: Create migrations**

```ruby
class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :search, null: false, foreign_key: true
      t.references :icp_definition, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.jsonb :stats, null: false, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end
```

```ruby
class CreateRunSourceExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :run_source_executions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :run, null: false, foreign_key: true
      t.string :source_key, null: false
      t.string :status, null: false, default: "pending"
      t.integer :hits_count, null: false, default: 0
      t.integer :cost_cents, null: false, default: 0
      t.text :error_message
      t.timestamps
    end
  end
end
```

```ruby
class CreateRawHits < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_hits do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :run_source_execution, null: false, foreign_key: true
      t.string :source_key, null: false
      t.string :source_uid, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :raw_hits, [ :workspace_id, :source_key, :source_uid ]
  end
end
```

```ruby
class AddRawHitFkToEvidences < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :evidences, :raw_hits
  end
end
```

- [ ] **Step 4: Write the models**

`app/models/run.rb`:

```ruby
class Run < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :workspace
  belongs_to :search
  belongs_to :icp_definition
  has_many :run_source_executions, dependent: :destroy
  has_many :raw_hits, through: :run_source_executions

  validates :status, inclusion: { in: STATUSES }

  # Increments a counter inside the stats jsonb. Uses a row lock because
  # source executions run concurrently and would otherwise clobber each other.
  def record_stats!(key, amount)
    with_lock do
      stats[key.to_s] = stats.fetch(key.to_s, 0) + amount
      save!
    end
  end
end
```

`app/models/run_source_execution.rb`:

```ruby
class RunSourceExecution < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :workspace
  belongs_to :run
  has_many :raw_hits, dependent: :destroy

  validates :source_key, presence: true
  validates :status, inclusion: { in: STATUSES }
end
```

`app/models/raw_hit.rb`:

```ruby
# Verbatim source payload. Immutable by design: raw hits are the replay buffer
# that lets improved normalisation re-derive canonical records without
# re-fetching, which for paid sources costs money again.
class RawHit < ApplicationRecord
  belongs_to :workspace
  belongs_to :run_source_execution
  has_many :evidences, dependent: :nullify

  validates :source_key, :source_uid, :fetched_at, presence: true

  after_initialize { readonly! if persisted? }
end
```

Add to `app/models/search.rb`:

```ruby
  has_many :runs, dependent: :destroy
```

- [ ] **Step 5: Run tests**

Run: `bin/rails db:migrate && bin/rails test test/models/run_test.rb`
Expected: PASS — 4 runs, 0 failures

- [ ] **Step 6: Commit**

```bash
git add db/ app/models/ test/models/run_test.rb
git commit -m "Add run tracking with immutable raw hits

Raw hits are readonly after create so the replay buffer cannot be
corrupted. Source execution failures are recorded per-source and do not
fail the whole run."
```

---

### Task 4: Adapter contract and registry

**Files:**
- Create: `app/services/sources/hit.rb`, `adapter.rb`, `registry.rb`
- Test: `test/services/sources/registry_test.rb`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `Sources::Hit = Data.define(:source_uid, :payload, :observed_at)`
  - `Sources::Adapter` abstract base. Subclasses define `self.key`, `self.manifest`, and `#search(params) → Array<Sources::Hit>`
  - `Sources::Manifest = Data.define(:accepted_params, :returned_fields, :cost_cents_per_call, :risk_level)` where `risk_level` is `:none`, `:tos_risk`, or `:paid`
  - `Sources::Registry.register(klass)`, `Sources::Registry.fetch(key) → Class`, `Sources::Registry.keys → Array<String>`

- [ ] **Step 1: Write the failing test**

Create `test/services/sources/registry_test.rb`:

```ruby
require "test_helper"

class Sources::RegistryTest < ActiveSupport::TestCase
  class FakeAdapter < Sources::Adapter
    def self.key = "fake"

    def self.manifest
      Sources::Manifest.new(
        accepted_params: [ :query ], returned_fields: [ :name ],
        cost_cents_per_call: 0, risk_level: :none
      )
    end

    def search(params)
      [ Sources::Hit.new(source_uid: "1", payload: { "q" => params[:query] }, observed_at: Time.current) ]
    end
  end

  setup { Sources::Registry.register(FakeAdapter) }
  teardown { Sources::Registry.reset! }

  test "fetches a registered adapter by key" do
    assert_equal FakeAdapter, Sources::Registry.fetch("fake")
  end

  test "raises a helpful error for an unknown key" do
    error = assert_raises(Sources::Registry::UnknownAdapter) { Sources::Registry.fetch("nope") }
    assert_match "nope", error.message
  end

  test "lists registered keys" do
    assert_includes Sources::Registry.keys, "fake"
  end

  test "an adapter returns hits" do
    hits = FakeAdapter.new.search(query: "rails")

    assert_equal 1, hits.length
    assert_equal "1", hits.first.source_uid
    assert_equal({ "q" => "rails" }, hits.first.payload)
  end

  test "the base adapter refuses to search" do
    assert_raises(NotImplementedError) { Sources::Adapter.new.search({}) }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/sources/registry_test.rb`
Expected: FAIL — `NameError: uninitialized constant Sources`

- [ ] **Step 3: Write the value objects and base class**

`app/services/sources/hit.rb`:

```ruby
module Sources
  # A single verbatim result from a source. Adapters return these and nothing
  # else: no scoring, no normalisation, no AI.
  Hit = Data.define(:source_uid, :payload, :observed_at)

  # Declares what an adapter accepts, what it returns, what it costs, and what
  # risk it carries. The registry surfaces this so the UI can warn before
  # enabling a ToS-risky or paid source.
  Manifest = Data.define(:accepted_params, :returned_fields, :cost_cents_per_call, :risk_level)
end
```

`app/services/sources/adapter.rb`:

```ruby
module Sources
  class Adapter
    def self.key
      raise NotImplementedError, "#{name} must define .key"
    end

    def self.manifest
      raise NotImplementedError, "#{name} must define .manifest"
    end

    def search(params)
      raise NotImplementedError, "#{self.class.name} must define #search"
    end
  end
end
```

`app/services/sources/registry.rb`:

```ruby
module Sources
  module Registry
    UnknownAdapter = Class.new(StandardError)

    class << self
      def register(klass)
        adapters[klass.key] = klass
      end

      def fetch(key)
        adapters.fetch(key.to_s) do
          raise UnknownAdapter, "no source adapter registered for #{key.inspect} (known: #{keys.join(', ')})"
        end
      end

      def keys = adapters.keys

      def reset! = @adapters = {}

      private
        def adapters = (@adapters ||= {})
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/sources/registry_test.rb`
Expected: PASS — 5 runs, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/sources/ test/services/sources/
git commit -m "Add source adapter contract, manifest, and registry

Adapters return verbatim hits only. The manifest declares cost and risk
level so the UI can warn before a paid or ToS-risky source is enabled."
```

---

### Task 5: Hacker News "Who is Hiring" adapter

**Files:**
- Create: `app/services/sources/hacker_news_who_is_hiring.rb`
- Create: `test/fixtures/files/hn_stories.json`, `test/fixtures/files/hn_comments.json`
- Test: `test/services/sources/hacker_news_who_is_hiring_test.rb`

**Interfaces:**
- Consumes: `Sources::Adapter`, `Sources::Hit`, `Sources::Manifest`, `Sources::Registry` (Task 4)
- Produces: `Sources::HackerNewsWhoIsHiring` with key `"hn_who_is_hiring"`. `#search(params) → Array<Sources::Hit>` where each hit's `source_uid` is the HN comment `objectID` and `payload` is the verbatim comment hash. Accepts `params[:max_pages]` (default 5).

**Background — verified API behaviour.** Two endpoints, both public and unauthenticated:

1. `https://hn.algolia.com/api/v1/search_by_date?tags=story,author_whoishiring&hitsPerPage=10` lists the monthly threads, newest first.
2. `https://hn.algolia.com/api/v1/search_by_date?tags=comment,story_<id>&hitsPerPage=100&page=<n>` returns that thread's comments.

Two traps, both confirmed against the live API:

- The `whoishiring` account posts **two** threads at the same timestamp each month: "Ask HN: Who is hiring?" and "Ask HN: Who wants to be hired?". Only the first is wanted. Filter on the title.
- Replies are returned alongside job posts. **A top-level job post has `parent_id == story_id`.** On a sampled page only 23 of 50 comments were top-level. Without this filter roughly half the hits are noise like "Incorrect."

- [ ] **Step 1: Create the test fixtures**

Create `test/fixtures/files/hn_stories.json`:

```json
{
  "hits": [
    { "objectID": "49522897", "title": "Ask HN: Who is hiring? (September 2026)", "created_at": "2026-09-01T15:01:17Z" },
    { "objectID": "49522896", "title": "Ask HN: Who wants to be hired? (September 2026)", "created_at": "2026-09-01T15:01:17Z" }
  ]
}
```

Create `test/fixtures/files/hn_comments.json`:

```json
{
  "nbPages": 1,
  "hits": [
    {
      "objectID": "49523001",
      "author": "ceo_acme",
      "comment_text": "Acme Analytics (https:&#x2F;&#x2F;acme.com) | Senior Rails Engineer | REMOTE | Bristol, UK<p>We are hiring.",
      "created_at": "2026-09-01T16:00:00Z",
      "parent_id": 49522897,
      "story_id": 49522897,
      "story_title": "Ask HN: Who is hiring? (September 2026)"
    },
    {
      "objectID": "49523002",
      "author": "someone",
      "comment_text": "Is this remote only?",
      "created_at": "2026-09-01T16:05:00Z",
      "parent_id": 49523001,
      "story_id": 49522897,
      "story_title": "Ask HN: Who is hiring? (September 2026)"
    }
  ]
}
```

- [ ] **Step 2: Write the failing test**

Create `test/services/sources/hacker_news_who_is_hiring_test.rb`:

```ruby
require "test_helper"

class Sources::HackerNewsWhoIsHiringTest < ActiveSupport::TestCase
  STORIES_URL = "https://hn.algolia.com/api/v1/search_by_date"

  setup do
    @adapter = Sources::HackerNewsWhoIsHiring.new
    stub_stories
    stub_comments
  end

  test "is registered under its key" do
    assert_equal Sources::HackerNewsWhoIsHiring, Sources::Registry.fetch("hn_who_is_hiring")
  end

  test "returns only top-level job posts" do
    hits = @adapter.search({})

    assert_equal 1, hits.length
    assert_equal "49523001", hits.first.source_uid
  end

  test "preserves the payload verbatim" do
    hit = @adapter.search({}).first

    assert_equal "ceo_acme", hit.payload["author"]
    assert_includes hit.payload["comment_text"], "Acme Analytics"
  end

  test "sets observed_at from the comment timestamp" do
    hit = @adapter.search({}).first

    assert_equal Time.parse("2026-09-01T16:00:00Z"), hit.observed_at
  end

  test "selects the hiring thread and not the wants-to-be-hired thread" do
    @adapter.search({})

    assert_requested :get, STORIES_URL, query: hash_including("tags" => "comment,story_49522897")
  end

  test "raises when no hiring thread can be found" do
    stub_request(:get, STORIES_URL)
      .with(query: hash_including("tags" => "story,author_whoishiring"))
      .to_return(body: { "hits" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Sources::HackerNewsWhoIsHiring::ThreadNotFound) { @adapter.search({}) }
  end

  test "raises on a non-success response" do
    stub_request(:get, STORIES_URL)
      .with(query: hash_including("tags" => "story,author_whoishiring"))
      .to_return(status: 503)

    assert_raises(Sources::HackerNewsWhoIsHiring::RequestFailed) { @adapter.search({}) }
  end

  private
    def stub_stories
      stub_request(:get, STORIES_URL)
        .with(query: hash_including("tags" => "story,author_whoishiring"))
        .to_return(
          body: file_fixture("hn_stories.json").read,
          headers: { "Content-Type" => "application/json" }
        )
    end

    def stub_comments
      stub_request(:get, STORIES_URL)
        .with(query: hash_including("tags" => "comment,story_49522897"))
        .to_return(
          body: file_fixture("hn_comments.json").read,
          headers: { "Content-Type" => "application/json" }
        )
    end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/services/sources/hacker_news_who_is_hiring_test.rb`
Expected: FAIL — `NameError: uninitialized constant Sources::HackerNewsWhoIsHiring`

- [ ] **Step 4: Write the adapter**

`app/services/sources/hacker_news_who_is_hiring.rb`:

```ruby
require "net/http"

module Sources
  # Sources job posts from the monthly "Ask HN: Who is hiring?" thread via the
  # public Algolia HN API. Free, unauthenticated, geography-agnostic, and dense
  # with funded startups actively looking for developers.
  class HackerNewsWhoIsHiring < Adapter
    ENDPOINT = "https://hn.algolia.com/api/v1/search_by_date".freeze
    HIRING_TITLE = /who is hiring/i
    DEFAULT_MAX_PAGES = 5
    PAGE_SIZE = 100

    ThreadNotFound = Class.new(StandardError)
    RequestFailed = Class.new(StandardError)

    def self.key = "hn_who_is_hiring"

    def self.manifest
      Manifest.new(
        accepted_params: [ :max_pages ],
        returned_fields: [ :comment_text, :author, :created_at ],
        cost_cents_per_call: 0,
        risk_level: :none
      )
    end

    def search(params)
      story_id = latest_hiring_story_id
      max_pages = params.fetch(:max_pages, DEFAULT_MAX_PAGES)

      collect_comments(story_id, max_pages).map do |comment|
        Hit.new(
          source_uid: comment["objectID"],
          payload: comment,
          observed_at: Time.parse(comment["created_at"])
        )
      end
    end

    private
      # The whoishiring account posts two threads at the same timestamp each
      # month; only "Who is hiring?" carries job posts.
      def latest_hiring_story_id
        stories = get(tags: "story,author_whoishiring", hitsPerPage: 10).fetch("hits", [])
        story = stories.find { |hit| hit["title"].to_s.match?(HIRING_TITLE) }
        raise ThreadNotFound, "no 'Who is hiring?' thread found" if story.nil?

        story["objectID"]
      end

      # Only comments whose parent is the story itself are job posts; the rest
      # are replies and discussion.
      def collect_comments(story_id, max_pages)
        (0...max_pages).flat_map do |page|
          body = get(tags: "comment,story_#{story_id}", hitsPerPage: PAGE_SIZE, page: page)
          hits = body.fetch("hits", [])
          top_level = hits.select { |hit| hit["parent_id"].to_s == hit["story_id"].to_s }

          break top_level if hits.empty? || page >= body.fetch("nbPages", 1) - 1

          top_level
        end
      end

      def get(query)
        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(query)
        response = Net::HTTP.get_response(uri)

        unless response.is_a?(Net::HTTPSuccess)
          raise RequestFailed, "HN API returned #{response.code} for #{uri}"
        end

        JSON.parse(response.body)
      end
  end

  Registry.register(HackerNewsWhoIsHiring)
end
```

- [ ] **Step 5: Ensure the adapter is loaded**

Rails autoloads `app/services`, but `Registry.register` only runs when the file is loaded. Create `config/initializers/sources.rb`:

```ruby
Rails.application.config.to_prepare do
  Sources::Registry.reset!
  Sources::Registry.register(Sources::HackerNewsWhoIsHiring)
end
```

Then remove the trailing `Registry.register(HackerNewsWhoIsHiring)` line from the adapter file — registration belongs in one place.

- [ ] **Step 6: Run tests**

Run: `bin/rails test test/services/sources/`
Expected: PASS — 12 runs, 0 failures

- [ ] **Step 7: Verify against the live API manually**

Run:

```bash
bin/rails runner 'hits = Sources::HackerNewsWhoIsHiring.new.search(max_pages: 1); puts hits.length; puts hits.first.payload["comment_text"][0, 200]'
```

Expected: a non-zero count and a real job post. This is a manual smoke check, not a test — tests never hit the network.

- [ ] **Step 8: Commit**

```bash
git add app/services/sources/ config/initializers/sources.rb test/
git commit -m "Add Hacker News Who is Hiring source adapter

Filters to top-level comments (parent_id == story_id) because roughly
half of a thread's comments are replies, and selects the hiring thread by
title because the whoishiring account posts two threads per month at the
same timestamp."
```

---

### Task 6: Normalizing HN posts into company attributes and evidence

**Files:**
- Create: `app/services/normalizers/hacker_news_post.rb`
- Test: `test/services/normalizers/hacker_news_post_test.rb`

**Interfaces:**
- Consumes: `RawHit` (Task 3), `CompanyIdentifier::KINDS` (Task 2)
- Produces:
  - `Normalizers::Result = Data.define(:company_attrs, :identifiers, :evidence_attrs)`
  - `Normalizers::HackerNewsPost.new(raw_hit).call → Normalizers::Result`
  - `evidence_attrs` is an Array of Hashes ready to pass to `Evidence.create!`, each already carrying `attribute_name`, `value`, `source_key`, `source_url`, `fetched_at`

**Background.** HN job posts conventionally use a pipe-delimited header line:
`Company (url) | Role | REMOTE | Location`. The format is a convention, not a rule, so the parser extracts what it can and stays silent about the rest. `comment_text` is HTML with escaped entities.

- [ ] **Step 1: Write the failing test**

Create `test/services/normalizers/hacker_news_post_test.rb`:

```ruby
require "test_helper"

class Normalizers::HackerNewsPostTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    icp = search.icp_definitions.create!(brief: "b")
    run = search.runs.create!(workspace: @workspace, icp_definition: icp)
    @execution = run.run_source_executions.create!(workspace: @workspace, source_key: "hn_who_is_hiring")
  end

  test "extracts company name, domain, and location from a conventional header" do
    result = normalize(
      "Acme Analytics (https:&#x2F;&#x2F;acme.com) | Senior Rails Engineer | REMOTE | Bristol, UK<p>We are hiring."
    )

    assert_equal "Acme Analytics", result.company_attrs[:name]
    assert_equal "acme.com", result.company_attrs[:domain]
    assert_equal "Bristol, UK", result.company_attrs[:location]
  end

  test "produces a domain identifier and a normalized name identifier" do
    result = normalize("Acme Analytics (https:&#x2F;&#x2F;acme.com) | Engineer | Bristol")

    assert_includes result.identifiers, { kind: "domain", value: "acme.com" }
    assert_includes result.identifiers, { kind: "normalized_name", value: "acme analytics" }
  end

  test "falls back to the name alone when there is no url" do
    result = normalize("Basalt Interactive | Backend Engineer | Berlin")

    assert_equal "Basalt Interactive", result.company_attrs[:name]
    assert_nil result.company_attrs[:domain]
    assert_equal [ { kind: "normalized_name", value: "basalt interactive" } ], result.identifiers
  end

  test "strips www and trailing slashes from the domain" do
    result = normalize("Acme (https:&#x2F;&#x2F;www.acme.com&#x2F;) | Engineer")

    assert_equal "acme.com", result.company_attrs[:domain]
  end

  test "builds evidence for every extracted attribute" do
    result = normalize("Acme Analytics (https:&#x2F;&#x2F;acme.com) | Engineer | REMOTE | Bristol, UK")
    names = result.evidence_attrs.map { |e| e[:attribute_name] }

    assert_includes names, "name"
    assert_includes names, "domain"
    assert_includes names, "location"
    assert(result.evidence_attrs.all? { |e| e[:source_key] == "hn_who_is_hiring" })
    assert(result.evidence_attrs.all? { |e| e[:source_url].present? })
  end

  test "evidence links back to the hacker news comment" do
    result = normalize("Acme (https:&#x2F;&#x2F;acme.com) | Engineer")

    assert_equal "https://news.ycombinator.com/item?id=49523001",
                 result.evidence_attrs.first[:source_url]
  end

  test "returns a blank result when the post has no parseable header" do
    result = normalize("we are looking for people, email me")

    assert_nil result.company_attrs[:name]
    assert_empty result.identifiers
    assert_empty result.evidence_attrs
  end

  private
    def normalize(comment_text)
      raw_hit = @execution.raw_hits.create!(
        workspace: @workspace,
        source_key: "hn_who_is_hiring",
        source_uid: "49523001",
        payload: { "objectID" => "49523001", "comment_text" => comment_text,
                   "created_at" => "2026-09-01T16:00:00Z" },
        fetched_at: Time.current
      )
      Normalizers::HackerNewsPost.new(raw_hit).call
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/normalizers/hacker_news_post_test.rb`
Expected: FAIL — `NameError: uninitialized constant Normalizers`

- [ ] **Step 3: Write the normalizer**

`app/services/normalizers/hacker_news_post.rb`:

```ruby
module Normalizers
  Result = Data.define(:company_attrs, :identifiers, :evidence_attrs)

  # Parses a Hacker News "Who is hiring?" job post into canonical company
  # attributes plus the evidence backing each one.
  #
  # The conventional header is "Company (url) | Role | REMOTE | Location", but
  # it is a convention rather than a rule. We extract what is confidently
  # present and stay silent about the rest: a wrong attribute is worse than a
  # missing one, because a wrong one gets scored.
  class HackerNewsPost
    SOURCE_KEY = "hn_who_is_hiring".freeze
    LOCATION_NOISE = /\A(remote|onsite|visa|interns?|full[- ]time|part[- ]time)\z/i

    def initialize(raw_hit)
      @raw_hit = raw_hit
      @payload = raw_hit.payload
    end

    def call
      return blank_result if name.blank?

      Result.new(
        company_attrs: { name: name, domain: domain, location: location }.compact,
        identifiers: identifiers,
        evidence_attrs: evidence_attrs
      )
    end

    private
      def blank_result = Result.new(company_attrs: {}, identifiers: [], evidence_attrs: [])

      def text
        @text ||= CGI.unescapeHTML(@payload["comment_text"].to_s)
      end

      # The header is everything before the first paragraph break.
      def segments
        @segments ||= text.split(/<p>/).first.to_s.split("|").map(&:strip)
      end

      def name
        return @name if defined?(@name)

        raw = segments.first.to_s.sub(/\(.*\z/, "").strip
        @name = raw.match?(/\A[[:alnum:]]/) && segments.length > 1 ? raw : nil
      end

      def domain
        return @domain if defined?(@domain)

        url = segments.first.to_s[/\((https?:\/\/[^)\s]+)\)/, 1]
        @domain = url && URI.parse(url).host&.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        @domain = nil
      end

      def location
        @location ||= segments[1..].to_a.reverse.find do |segment|
          segment.present? && !segment.match?(LOCATION_NOISE) && segment.length < 60 && segment.include?(",")
        end
      end

      def identifiers
        list = []
        list << { kind: "domain", value: domain } if domain.present?
        list << { kind: "normalized_name", value: name.downcase.strip } if name.present?
        list
      end

      def source_url
        "https://news.ycombinator.com/item?id=#{@payload['objectID']}"
      end

      def evidence_attrs
        { "name" => name, "domain" => domain, "location" => location }.compact.map do |attribute, value|
          {
            attribute_name: attribute,
            value: value,
            source_key: SOURCE_KEY,
            source_url: source_url,
            fetched_at: @raw_hit.fetched_at,
            raw_hit_id: @raw_hit.id,
            confidence: 0.8
          }
        end
      end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/normalizers/`
Expected: PASS — 7 runs, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/normalizers/ test/services/normalizers/
git commit -m "Add Hacker News post normalizer

Extracts company name, domain, and location from the conventional
pipe-delimited header, emitting an Evidence record for each extracted
attribute. Stays silent when the header is unparseable: a wrong attribute
is worse than a missing one because a wrong one gets scored."
```

---

### Task 7: Pipeline orchestration and lead creation

**Files:**
- Create: `db/migrate/*_create_leads.rb`, `*_create_lead_discoveries.rb`
- Create: `app/models/lead.rb`, `lead_discovery.rb`
- Create: `app/jobs/run_search_job.rb`
- Test: `test/jobs/run_search_job_test.rb`

**Interfaces:**
- Consumes: everything from Tasks 1–6
- Produces:
  - `Lead` with `status` in `%w[new reviewing qualified disqualified nurture]`, unique on `[workspace_id, company_id]`
  - `LeadDiscovery` joining `lead`, `run`, `search`
  - `RunSearchJob.perform_later(search)` — executes the full pipeline for one search, creating a `Run`

- [ ] **Step 1: Write the failing test**

Create `test/jobs/run_search_job_test.rb`:

```ruby
require "test_helper"

class RunSearchJobTest < ActiveJob::TestCase
  STORIES_URL = "https://hn.algolia.com/api/v1/search_by_date"

  setup do
    @workspace = Workspace.create!(name: "Personal")
    @search = @workspace.searches.create!(name: "HN", status: "active")
    @search.icp_definitions.create!(brief: "Funded startups needing Rails help")
    @search.search_sources.create!(workspace: @workspace, adapter_key: "hn_who_is_hiring")
    stub_hn
  end

  test "creates a completed run pinned to the active icp definition" do
    RunSearchJob.perform_now(@search)
    run = @search.runs.sole

    assert_equal "completed", run.status
    assert_equal @search.active_icp_definition, run.icp_definition
    assert run.finished_at.present?
  end

  test "stores raw hits verbatim" do
    RunSearchJob.perform_now(@search)

    assert_equal 1, RawHit.count
    assert_equal "49523001", RawHit.sole.source_uid
  end

  test "creates a company with evidence for each attribute" do
    RunSearchJob.perform_now(@search)
    company = Company.sole

    assert_equal "Acme Analytics", company.name
    assert_equal "acme.com", company.domain
    assert_equal %w[domain location name], company.evidences.order(:attribute_name).pluck(:attribute_name)
  end

  test "creates one lead and records its discovery" do
    RunSearchJob.perform_now(@search)

    assert_equal 1, Lead.count
    assert_equal "new", Lead.sole.status
    assert_equal @search, LeadDiscovery.sole.search
  end

  test "a second run does not duplicate the lead but records a second discovery" do
    RunSearchJob.perform_now(@search)
    RunSearchJob.perform_now(@search)

    assert_equal 1, Lead.count
    assert_equal 2, LeadDiscovery.count
  end

  test "records per-source failure without failing the run" do
    stub_request(:get, STORIES_URL).to_return(status: 503)

    RunSearchJob.perform_now(@search)
    run = @search.runs.sole

    assert_equal "completed", run.status
    assert_equal "failed", run.run_source_executions.sole.status
    assert_match "503", run.run_source_executions.sole.error_message
  end

  test "records run statistics" do
    RunSearchJob.perform_now(@search)

    assert_equal 1, @search.runs.sole.stats["hits_found"]
    assert_equal 1, @search.runs.sole.stats["leads_created"]
  end

  private
    def stub_hn
      stub_request(:get, STORIES_URL)
        .with(query: hash_including("tags" => "story,author_whoishiring"))
        .to_return(body: file_fixture("hn_stories.json").read,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, STORIES_URL)
        .with(query: hash_including("tags" => "comment,story_49522897"))
        .to_return(body: file_fixture("hn_comments.json").read,
                   headers: { "Content-Type" => "application/json" })
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/run_search_job_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'search_sources'`

- [ ] **Step 3: Create migrations**

```ruby
class CreateSearchSources < ActiveRecord::Migration[8.1]
  def change
    create_table :search_sources do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :search, null: false, foreign_key: true
      t.string :adapter_key, null: false
      t.jsonb :adapter_params, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :search_sources, [ :search_id, :adapter_key ], unique: true
  end
end
```

```ruby
class CreateLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :leads do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :person, foreign_key: true
      t.string :status, null: false, default: "new"
      t.datetime :snoozed_until
      t.timestamps
    end
    add_index :leads, [ :workspace_id, :company_id ], unique: true
  end
end
```

```ruby
class CreateLeadDiscoveries < ActiveRecord::Migration[8.1]
  def change
    create_table :lead_discoveries do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :run, null: false, foreign_key: true
      t.references :search, null: false, foreign_key: true
      t.datetime :discovered_at, null: false
      t.timestamps
    end
  end
end
```

- [ ] **Step 4: Write the models**

`app/models/search_source.rb`:

```ruby
class SearchSource < ApplicationRecord
  belongs_to :workspace
  belongs_to :search

  validates :adapter_key, presence: true

  scope :enabled, -> { where(enabled: true) }

  def adapter = Sources::Registry.fetch(adapter_key).new

  def symbolized_params = adapter_params.symbolize_keys
end
```

`app/models/lead.rb`:

```ruby
class Lead < ApplicationRecord
  STATUSES = %w[new reviewing qualified disqualified nurture].freeze

  belongs_to :workspace
  belongs_to :company
  belongs_to :person, optional: true
  has_many :lead_discoveries, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
end
```

`app/models/lead_discovery.rb`:

```ruby
class LeadDiscovery < ApplicationRecord
  belongs_to :workspace
  belongs_to :lead
  belongs_to :run
  belongs_to :search
end
```

Add to `app/models/search.rb`:

```ruby
  has_many :search_sources, dependent: :destroy
```

Add to `app/models/workspace.rb`:

```ruby
  has_many :leads, dependent: :destroy
```

- [ ] **Step 5: Write the orchestrator job**

`app/jobs/run_search_job.rb`:

```ruby
# Executes the full pipeline for one search: discover, normalize, dedupe, and
# create leads. Each source runs in its own begin/rescue so that a blocked or
# broken source fails one stage of one run rather than the whole run.
class RunSearchJob < ApplicationJob
  queue_as :default

  NORMALIZERS = { "hn_who_is_hiring" => Normalizers::HackerNewsPost }.freeze

  def perform(search)
    icp = search.active_icp_definition
    raise ArgumentError, "search #{search.id} has no ICP definition" if icp.nil?

    run = search.runs.create!(
      workspace: search.workspace, icp_definition: icp,
      status: "running", started_at: Time.current
    )

    search.search_sources.enabled.each { |source| execute_source(run, source) }

    run.update!(status: "completed", finished_at: Time.current)
  end

  private
    def execute_source(run, source)
      execution = run.run_source_executions.create!(
        workspace: run.workspace, source_key: source.adapter_key, status: "running"
      )

      hits = source.adapter.search(source.symbolized_params)
      hits.each { |hit| ingest(run, execution, source, hit) }

      execution.update!(status: "completed", hits_count: hits.length)
      run.record_stats!(:hits_found, hits.length)
    rescue StandardError => error
      execution.update!(status: "failed", error_message: "#{error.class}: #{error.message}")
      Rails.logger.error("source #{source.adapter_key} failed on run #{run.id}: #{error.message}")
    end

    def ingest(run, execution, source, hit)
      raw_hit = execution.raw_hits.create!(
        workspace: run.workspace, source_key: source.adapter_key,
        source_uid: hit.source_uid, payload: hit.payload, fetched_at: hit.observed_at
      )

      result = NORMALIZERS.fetch(source.adapter_key).new(raw_hit).call
      return if result.identifiers.empty?

      company = IdentityResolver.new(workspace: run.workspace)
        .resolve(identifiers: result.identifiers, attrs: result.company_attrs)

      create_evidence(run, company, result)
      record_lead(run, company)
    end

    def create_evidence(run, company, result)
      result.evidence_attrs.each do |attrs|
        next if company.evidences.exists?(
          attribute_name: attrs[:attribute_name], source_url: attrs[:source_url]
        )

        company.evidences.create!(attrs.merge(workspace: run.workspace))
      end
    end

    def record_lead(run, company)
      lead = Lead.find_or_create_by!(workspace: run.workspace, company: company)
      run.record_stats!(:leads_created, 1) if lead.previously_new_record?

      lead.lead_discoveries.create!(
        workspace: run.workspace, run: run, search: run.search, discovered_at: Time.current
      )
    end
end
```

- [ ] **Step 6: Run tests**

Run: `bin/rails db:migrate && bin/rails test test/jobs/run_search_job_test.rb`
Expected: PASS — 7 runs, 0 failures

- [ ] **Step 7: Run the whole suite**

Run: `bin/rails test`
Expected: PASS — all tests green

- [ ] **Step 8: Commit**

```bash
git add db/ app/models/ app/jobs/ test/
git commit -m "Add pipeline orchestration and lead creation

Each source executes inside its own rescue so a blocked source fails one
stage of one run. Leads are per-company with a discoveries join, so a
company found by several searches is one inbox item carrying a stronger
signal rather than three duplicates."
```

---

### Task 8: Lead list UI and Fly.io deployment

**Files:**
- Create: `app/controllers/leads_controller.rb`, `app/views/leads/index.html.erb`, `app/views/leads/show.html.erb`
- Create: `fly.toml`
- Modify: `config/routes.rb`, `db/seeds.rb`
- Test: `test/controllers/leads_controller_test.rb`

**Interfaces:**
- Consumes: `Lead`, `Company`, `Evidence` (Tasks 2, 7)
- Produces: `GET /leads` and `GET /leads/:id`. `Current.workspace` helper resolving the single workspace.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/leads_controller_test.rb`:

```ruby
require "test_helper"

class LeadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @company = @workspace.companies.create!(name: "Acme Analytics", domain: "acme.com")
    @lead = Lead.create!(workspace: @workspace, company: @company)
    @company.evidences.create!(
      workspace: @workspace, attribute_name: "domain", value: "acme.com",
      source_key: "hn_who_is_hiring",
      source_url: "https://news.ycombinator.com/item?id=1", fetched_at: Time.current
    )
  end

  test "index lists leads" do
    get leads_url

    assert_response :success
    assert_select "[data-lead-id='#{@lead.id}']"
    assert_match "Acme Analytics", response.body
  end

  test "show displays the company and its evidence with source links" do
    get lead_url(@lead)

    assert_response :success
    assert_match "acme.com", response.body
    assert_select "a[href='https://news.ycombinator.com/item?id=1']"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/leads_controller_test.rb`
Expected: FAIL — `NameError: undefined local variable or method 'leads_url'`

- [ ] **Step 3: Add the current-workspace helper**

Create `app/models/current.rb`:

```ruby
# Single-workspace resolution for now. When multi-tenancy arrives this becomes
# a per-request attribute set from the session rather than a lookup.
class Current < ActiveSupport::CurrentAttributes
  attribute :workspace

  def workspace
    super || self.workspace = Workspace.first!
  end
end
```

- [ ] **Step 4: Write the controller, routes, and views**

`app/controllers/leads_controller.rb`:

```ruby
class LeadsController < ApplicationController
  def index
    @leads = Current.workspace.leads
      .includes(:company)
      .order(created_at: :desc)
  end

  def show
    @lead = Current.workspace.leads.includes(company: :evidences).find(params[:id])
  end
end
```

Modify `config/routes.rb` — add inside the `Rails.application.routes.draw` block:

```ruby
  resources :leads, only: [ :index, :show ]
  root "leads#index"
```

`app/views/leads/index.html.erb`:

```erb
<h1>Leads <span><%= @leads.size %></span></h1>

<ul class="leads">
  <% @leads.each do |lead| %>
    <li data-lead-id="<%= lead.id %>">
      <%= link_to lead.company.name.presence || "Unnamed company", lead_path(lead) %>
      <span class="domain"><%= lead.company.domain %></span>
      <span class="status"><%= lead.status %></span>
    </li>
  <% end %>
</ul>
```

`app/views/leads/show.html.erb`:

```erb
<h1><%= @lead.company.name %></h1>
<p><%= @lead.company.domain %> &middot; <%= @lead.company.location %></p>

<h2>Evidence</h2>
<ul class="evidence">
  <% @lead.company.evidences.order(:attribute_name).each do |evidence| %>
    <li>
      <strong><%= evidence.attribute_name %></strong>: <%= evidence.value %>
      <%= link_to evidence.source_key, evidence.source_url %>
      <time><%= evidence.fetched_at.to_fs(:short) %></time>
    </li>
  <% end %>
</ul>
```

- [ ] **Step 5: Add seeds for local development**

Replace `db/seeds.rb`:

```ruby
workspace = Workspace.find_or_create_by!(name: "Personal")

search = workspace.searches.find_or_create_by!(name: "HN Who is Hiring") do |record|
  record.status = "active"
end

search.icp_definitions.find_or_create_by!(version: 1) do |record|
  record.brief = "Funded startups and small product companies hiring backend or " \
                 "full-stack developers, who would plausibly outsource a build."
end

search.search_sources.find_or_create_by!(adapter_key: "hn_who_is_hiring") do |record|
  record.workspace = workspace
end

puts "Seeded workspace #{workspace.id} with search #{search.id}"
```

- [ ] **Step 6: Run tests and seed locally**

Run:

```bash
bin/rails test
bin/rails db:seed
bin/rails runner 'RunSearchJob.perform_now(Search.first)'
bin/rails runner 'puts "leads: #{Lead.count}, companies: #{Company.count}, evidence: #{Evidence.count}"'
```

Expected: all tests pass; the runner reports a non-zero lead count against the live HN thread.

- [ ] **Step 7: Create the Fly configuration**

Create `fly.toml` (replace `<app-name>` and pick your region):

```toml
app = "<app-name>"
primary_region = "lhr"

[build]

[env]
  RAILS_ENV = "production"
  SOLID_QUEUE_IN_PUMA = "false"

[http_service]
  internal_port = 80
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0
  processes = ["web"]

[processes]
  web = "./bin/thrust ./bin/rails server"
  worker = "bundle exec rake solid_queue:start"

[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1
```

Then:

```bash
fly launch --no-deploy --copy-config
fly postgres create --name leads-pipeline-db
fly postgres attach leads-pipeline-db
fly secrets set RAILS_MASTER_KEY="$(cat config/master.key)"
fly deploy
fly ssh console -C "bin/rails db:seed"
```

- [ ] **Step 8: Commit**

```bash
git add app/ config/routes.rb db/seeds.rb fly.toml test/controllers/
git commit -m "Add lead list UI and Fly.io deployment config

Milestone 1 complete: a search runs end to end from the HN adapter to
canonical companies with linked evidence, viewable in the browser."
```

**Milestone 1 is complete.** Before starting Milestone 2, run one real search and read twenty leads by hand. The score thresholds in Task 13 are meant to be set from that observed distribution, not guessed.

---

# MILESTONE 2 — Scoring and the triage inbox

---

### Task 9: Suppressions

**Files:**
- Create: `db/migrate/*_create_suppressions.rb`, `app/models/suppression.rb`
- Modify: `app/jobs/run_search_job.rb`
- Test: `test/models/suppression_test.rb`, `test/jobs/run_search_job_test.rb`

**Interfaces:**
- Consumes: `Workspace`, `Company` (Tasks 1–2)
- Produces: `Suppression.suppressed?(workspace:, domain:) → Boolean`. Reasons: `%w[current_client competitor opted_out do_not_contact]`

- [ ] **Step 1: Write the failing test**

Create `test/models/suppression_test.rb`:

```ruby
require "test_helper"

class SuppressionTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @workspace.suppressions.create!(domain: "acme.com", reason: "current_client")
  end

  test "reports a suppressed domain" do
    assert Suppression.suppressed?(workspace: @workspace, domain: "acme.com")
  end

  test "matches case-insensitively" do
    assert Suppression.suppressed?(workspace: @workspace, domain: "ACME.com")
  end

  test "does not report an unsuppressed domain" do
    refute Suppression.suppressed?(workspace: @workspace, domain: "other.com")
  end

  test "treats a blank domain as unsuppressed" do
    refute Suppression.suppressed?(workspace: @workspace, domain: nil)
  end

  test "is scoped per workspace" do
    other = Workspace.create!(name: "Other")

    refute Suppression.suppressed?(workspace: other, domain: "acme.com")
  end

  test "requires a valid reason" do
    refute @workspace.suppressions.build(domain: "x.com", reason: "nonsense").valid?
  end
end
```

Add to `test/jobs/run_search_job_test.rb`:

```ruby
  test "does not create a lead for a suppressed domain" do
    @workspace.suppressions.create!(domain: "acme.com", reason: "current_client")

    RunSearchJob.perform_now(@search)

    assert_equal 0, Lead.count
    assert_equal 1, @search.runs.sole.stats["suppressed"]
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/suppression_test.rb test/jobs/run_search_job_test.rb`
Expected: FAIL — `NameError: uninitialized constant Suppression`

- [ ] **Step 3: Create the migration and model**

```ruby
class CreateSuppressions < ActiveRecord::Migration[8.1]
  def change
    create_table :suppressions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :domain
      t.string :email
      t.string :reason, null: false
      t.text :note
      t.timestamps
    end
    add_index :suppressions, [ :workspace_id, :domain ]
  end
end
```

`app/models/suppression.rb`:

```ruby
# Checked before anything reaches the review queue. Current clients,
# competitors, and anyone who has opted out must never be surfaced, and under
# GDPR the opt-out check is a requirement rather than a courtesy.
class Suppression < ApplicationRecord
  REASONS = %w[current_client competitor opted_out do_not_contact].freeze

  belongs_to :workspace

  validates :reason, inclusion: { in: REASONS }
  validate :domain_or_email_present

  def self.suppressed?(workspace:, domain:)
    return false if domain.blank?

    where(workspace: workspace).where("lower(domain) = ?", domain.downcase).exists?
  end

  private
    def domain_or_email_present
      errors.add(:base, "domain or email required") if domain.blank? && email.blank?
    end
end
```

Add to `app/models/workspace.rb`:

```ruby
  has_many :suppressions, dependent: :destroy
```

- [ ] **Step 4: Wire suppression into the pipeline**

In `app/jobs/run_search_job.rb`, replace the `record_lead` method:

```ruby
    def record_lead(run, company)
      if Suppression.suppressed?(workspace: run.workspace, domain: company.domain)
        run.record_stats!(:suppressed, 1)
        return
      end

      lead = Lead.find_or_create_by!(workspace: run.workspace, company: company)
      run.record_stats!(:leads_created, 1) if lead.previously_new_record?

      lead.lead_discoveries.create!(
        workspace: run.workspace, run: run, search: run.search, discovered_at: Time.current
      )
    end
```

- [ ] **Step 5: Run tests**

Run: `bin/rails db:migrate && bin/rails test`
Expected: PASS — all green

- [ ] **Step 6: Commit**

```bash
git add db/ app/models/suppression.rb app/jobs/run_search_job.rb test/
git commit -m "Add suppressions checked before leads reach the queue

Current clients, competitors, and opted-out contacts are never surfaced.
Under GDPR the opt-out check is a requirement, not a courtesy."
```

---

### Task 10: Anthropic client and cost ledger

**Files:**
- Create: `app/services/anthropic_client.rb`, `app/models/cost_ledger_entry.rb`
- Create: `db/migrate/*_create_cost_ledger_entries.rb`
- Modify: `config/credentials` usage — read from `ENV["ANTHROPIC_API_KEY"]`
- Test: `test/services/anthropic_client_test.rb`, `test/models/cost_ledger_entry_test.rb`

**Interfaces:**
- Consumes: `Workspace`
- Produces:
  - `AnthropicClient.instance → Anthropic::Client` (memoised)
  - `AnthropicClient.model → "claude-opus-5"`
  - `CostLedgerEntry.record!(workspace:, kind:, model:, usage:, subject: nil)` where `usage` responds to `input_tokens`, `output_tokens`, `cache_read_input_tokens`
  - `CostLedgerEntry#estimated_cost_cents → Integer`

**Pricing note.** `claude-opus-5` is $5.00 per million input tokens and $25.00 per million output tokens; cached reads bill at roughly a tenth of the input rate. These constants are an estimate for local visibility, not billing truth.

- [ ] **Step 1: Write the failing tests**

Create `test/models/cost_ledger_entry_test.rb`:

```ruby
require "test_helper"

class CostLedgerEntryTest < ActiveSupport::TestCase
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, keyword_init: true)

  setup { @workspace = Workspace.create!(name: "Personal") }

  test "records token counts from a usage object" do
    entry = CostLedgerEntry.record!(
      workspace: @workspace, kind: "scoring", model: "claude-opus-5",
      usage: Usage.new(input_tokens: 1_000, output_tokens: 500, cache_read_input_tokens: 4_000)
    )

    assert_equal 1_000, entry.input_tokens
    assert_equal 500, entry.output_tokens
    assert_equal 4_000, entry.cached_input_tokens
  end

  test "estimates cost in cents" do
    entry = CostLedgerEntry.record!(
      workspace: @workspace, kind: "scoring", model: "claude-opus-5",
      usage: Usage.new(input_tokens: 1_000_000, output_tokens: 0, cache_read_input_tokens: 0)
    )

    assert_equal 500, entry.estimated_cost_cents
  end

  test "prices cached reads at a tenth of the input rate" do
    entry = CostLedgerEntry.record!(
      workspace: @workspace, kind: "scoring", model: "claude-opus-5",
      usage: Usage.new(input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 1_000_000)
    )

    assert_equal 50, entry.estimated_cost_cents
  end

  test "tolerates a usage object without cache fields" do
    entry = CostLedgerEntry.record!(
      workspace: @workspace, kind: "scoring", model: "claude-opus-5",
      usage: Struct.new(:input_tokens, :output_tokens).new(10, 20)
    )

    assert_equal 0, entry.cached_input_tokens
  end
end
```

Create `test/services/anthropic_client_test.rb`:

```ruby
require "test_helper"

class AnthropicClientTest < ActiveSupport::TestCase
  test "uses claude-opus-5" do
    assert_equal "claude-opus-5", AnthropicClient.model
  end

  test "builds a client" do
    assert_kind_of Anthropic::Client, AnthropicClient.instance
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/cost_ledger_entry_test.rb test/services/anthropic_client_test.rb`
Expected: FAIL — `NameError: uninitialized constant CostLedgerEntry`

- [ ] **Step 3: Create the migration and model**

```ruby
class CreateCostLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :cost_ledger_entries do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: true
      t.string :kind, null: false
      t.string :model, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cached_input_tokens, null: false, default: 0
      t.timestamps
    end
    add_index :cost_ledger_entries, [ :workspace_id, :kind, :created_at ]
  end
end
```

`app/models/cost_ledger_entry.rb`:

```ruby
# Every model call is recorded so that an always-on system's spend is visible
# before the invoice. Prices are estimates for local visibility, not billing
# truth.
class CostLedgerEntry < ApplicationRecord
  INPUT_CENTS_PER_MTOK = 500
  OUTPUT_CENTS_PER_MTOK = 2_500
  CACHE_READ_DISCOUNT = 0.1

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true

  def self.record!(workspace:, kind:, model:, usage:, subject: nil)
    create!(
      workspace: workspace, kind: kind, model: model, subject: subject,
      input_tokens: read_usage(usage, :input_tokens),
      output_tokens: read_usage(usage, :output_tokens),
      cached_input_tokens: read_usage(usage, :cache_read_input_tokens)
    )
  end

  def self.read_usage(usage, field)
    usage.respond_to?(field) ? usage.public_send(field).to_i : 0
  end

  def estimated_cost_cents
    input = input_tokens * INPUT_CENTS_PER_MTOK
    output = output_tokens * OUTPUT_CENTS_PER_MTOK
    cached = cached_input_tokens * INPUT_CENTS_PER_MTOK * CACHE_READ_DISCOUNT

    ((input + output + cached) / 1_000_000.0).round
  end
end
```

Add to `app/models/workspace.rb`:

```ruby
  has_many :cost_ledger_entries, dependent: :destroy
```

- [ ] **Step 4: Write the client wrapper**

`app/services/anthropic_client.rb`:

```ruby
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
```

- [ ] **Step 5: Run tests**

Run: `ANTHROPIC_API_KEY=test-key bin/rails db:migrate && ANTHROPIC_API_KEY=test-key bin/rails test test/models/cost_ledger_entry_test.rb test/services/anthropic_client_test.rb`
Expected: PASS — 6 runs, 0 failures

Then add to `test/test_helper.rb` so every test run has a key present:

```ruby
ENV["ANTHROPIC_API_KEY"] ||= "test-key"
```

- [ ] **Step 6: Commit**

```bash
git add db/ app/models/cost_ledger_entry.rb app/services/anthropic_client.rb test/
git commit -m "Add configured Claude client and cost ledger

Model choice is centralised so downgrading a stage is a deliberate,
measured decision. Every call is recorded so an always-on system's spend
is visible before the invoice arrives."
```

---

### Task 11: Scoring prompt and the scorer

**Files:**
- Create: `app/services/scoring/rubric_prompt.rb`, `app/services/scoring/scorer.rb`
- Create: `db/migrate/*_create_scores.rb`, `app/models/score.rb`
- Test: `test/services/scoring/scorer_test.rb`, `test/models/score_test.rb`

**Interfaces:**
- Consumes: `Lead`, `IcpDefinition`, `Evidence`, `AnthropicClient`, `CostLedgerEntry`
- Produces:
  - `Scoring::RubricPrompt.new(icp_definition).system_blocks → Array<Hash>` — cacheable prefix
  - `Scoring::RubricPrompt::SCHEMA → Hash` — JSON schema for structured output
  - `Scoring::Scorer.new(lead:, icp_definition:).call → Score`
  - `Score` columns: `total`, `dimensions` jsonb, `rationale`, `cited_evidence_ids` integer array, `confidence`, `model`, `icp_definition_id`, `flagged_reason`

- [ ] **Step 1: Write the failing tests**

Create `test/models/score_test.rb`:

```ruby
require "test_helper"

class ScoreTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
    company = @workspace.companies.create!(name: "Acme")
    @lead = Lead.create!(workspace: @workspace, company: company)
  end

  test "is append-only" do
    score = Score.create!(
      workspace: @workspace, lead: @lead, icp_definition: @icp,
      total: 80, dimensions: { "fit" => 8 }, rationale: "r", model: "claude-opus-5"
    )

    assert_raises(ActiveRecord::ReadOnlyRecord) { score.update!(total: 90) }
  end

  test "lead exposes its latest score" do
    Score.create!(workspace: @workspace, lead: @lead, icp_definition: @icp,
                  total: 50, rationale: "old", model: "claude-opus-5")
    newest = Score.create!(workspace: @workspace, lead: @lead, icp_definition: @icp,
                           total: 80, rationale: "new", model: "claude-opus-5")

    assert_equal newest, @lead.reload.latest_score
  end

  test "rejects a total outside 0..100" do
    score = Score.new(workspace: @workspace, lead: @lead, icp_definition: @icp,
                      total: 120, rationale: "r", model: "claude-opus-5")
    refute score.valid?
  end
end
```

Create `test/services/scoring/scorer_test.rb`:

```ruby
require "test_helper"

class Scoring::ScorerTest < ActiveSupport::TestCase
  API_URL = "https://api.anthropic.com/v1/messages"

  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(
      brief: "Funded startups needing Rails help",
      scoring_rubric: { "dimensions" => { "fit" => 40, "timing" => 35, "reachability" => 25 } }
    )
    @company = @workspace.companies.create!(name: "Acme Analytics", domain: "acme.com")
    @evidence = @company.evidences.create!(
      workspace: @workspace, attribute_name: "name", value: "Acme Analytics",
      source_key: "hn_who_is_hiring", source_url: "https://news.ycombinator.com/item?id=1",
      fetched_at: Time.current
    )
    @lead = Lead.create!(workspace: @workspace, company: @company)
  end

  test "persists a score from the model response" do
    stub_model_response(total: 81, cited: [ @evidence.id ])

    score = Scoring::Scorer.new(lead: @lead, icp_definition: @icp).call

    assert_equal 81, score.total
    assert_equal "claude-opus-5", score.model
    assert_equal @icp, score.icp_definition
    assert_equal [ @evidence.id ], score.cited_evidence_ids
  end

  test "sends the rubric as a cacheable system prefix" do
    stub_model_response(total: 50, cited: [ @evidence.id ])

    Scoring::Scorer.new(lead: @lead, icp_definition: @icp).call

    assert_requested :post, API_URL do |request|
      body = JSON.parse(request.body)
      body["model"] == "claude-opus-5" &&
        body["cache_control"] == { "type" => "ephemeral" } &&
        body["output_config"]["format"]["type"] == "json_schema" &&
        body["system"].to_s.include?("Funded startups needing Rails help")
    end
  end

  test "records a cost ledger entry" do
    stub_model_response(total: 50, cited: [ @evidence.id ])

    assert_difference "CostLedgerEntry.count", 1 do
      Scoring::Scorer.new(lead: @lead, icp_definition: @icp).call
    end

    assert_equal "scoring", CostLedgerEntry.last.kind
  end

  test "flags a score citing an evidence id that does not exist" do
    stub_model_response(total: 95, cited: [ 999_999 ])

    score = Scoring::Scorer.new(lead: @lead, icp_definition: @icp).call

    assert score.flagged?
    assert_match "999999", score.flagged_reason
  end

  test "raises a wrapped error when the API fails" do
    stub_request(:post, API_URL).to_return(status: 500, body: "{}")

    assert_raises(Scoring::Scorer::ScoringFailed) do
      Scoring::Scorer.new(lead: @lead, icp_definition: @icp).call
    end
  end

  private
    def stub_model_response(total:, cited:)
      payload = {
        total: total,
        dimensions: { fit: 8, timing: 9, reachability: 5 },
        rationale: "Hiring Rails engineers shortly after funding.",
        cited_evidence_ids: cited,
        confidence: 0.8
      }

      stub_request(:post, API_URL).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          id: "msg_1", type: "message", role: "assistant", model: "claude-opus-5",
          content: [ { type: "text", text: payload.to_json } ],
          stop_reason: "end_turn",
          usage: { input_tokens: 1200, output_tokens: 300, cache_read_input_tokens: 4000 }
        }.to_json
      )
    end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/score_test.rb test/services/scoring/`
Expected: FAIL — `NameError: uninitialized constant Score`

- [ ] **Step 3: Create the migration and model**

```ruby
class CreateScores < ActiveRecord::Migration[8.1]
  def change
    create_table :scores do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :icp_definition, null: false, foreign_key: true
      t.integer :total, null: false
      t.jsonb :dimensions, null: false, default: {}
      t.text :rationale
      t.bigint :cited_evidence_ids, array: true, null: false, default: []
      t.float :confidence
      t.string :model, null: false
      t.text :flagged_reason
      t.timestamps
    end
    add_index :scores, [ :lead_id, :created_at ]
  end
end
```

`app/models/score.rb`:

```ruby
# Append-only. Re-scoring inserts a new row so that score drift is visible and
# two rubric versions can be diffed over the same lead set.
class Score < ApplicationRecord
  belongs_to :workspace
  belongs_to :lead
  belongs_to :icp_definition

  validates :total, presence: true, inclusion: { in: 0..100 }
  validates :model, presence: true

  after_initialize { readonly! if persisted? }

  def flagged? = flagged_reason.present?
end
```

Add to `app/models/lead.rb`:

```ruby
  has_many :scores, dependent: :destroy

  def latest_score = scores.order(created_at: :desc).first
```

- [ ] **Step 4: Write the prompt builder**

`app/services/scoring/rubric_prompt.rb`:

```ruby
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
```

- [ ] **Step 5: Write the scorer**

`app/services/scoring/scorer.rb`:

```ruby
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
```

- [ ] **Step 6: Run tests**

Run: `bin/rails db:migrate && bin/rails test test/models/score_test.rb test/services/scoring/`
Expected: FAIL — `NameError: uninitialized constant Scoring::EvidenceValidator`. That is expected; Task 12 supplies it.

- [ ] **Step 7: Commit the work-in-progress after Task 12**

Do not commit yet. Task 12 completes this unit.

---

### Task 12: The evidence citation validator

**Files:**
- Create: `app/services/scoring/evidence_validator.rb`
- Test: `test/services/scoring/evidence_validator_test.rb`

**Interfaces:**
- Consumes: `Lead`, `Evidence`
- Produces: `Scoring::EvidenceValidator.new(lead:, cited_ids:).failure_reason → String | nil`

**Why this exists.** A scoring model that fabricates its own justification is the most dangerous failure in the system, precisely because the output looks correct. Every cited id is checked against the evidence actually attached to that lead's company.

- [ ] **Step 1: Write the failing test**

Create `test/services/scoring/evidence_validator_test.rb`:

```ruby
require "test_helper"

class Scoring::EvidenceValidatorTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    @company = @workspace.companies.create!(name: "Acme")
    @evidence = @company.evidences.create!(
      workspace: @workspace, attribute_name: "name", value: "Acme",
      source_key: "hn_who_is_hiring", fetched_at: Time.current
    )
    @lead = Lead.create!(workspace: @workspace, company: @company)
  end

  test "passes when every cited id belongs to the lead" do
    validator = Scoring::EvidenceValidator.new(lead: @lead, cited_ids: [ @evidence.id ])

    assert_nil validator.failure_reason
  end

  test "fails when an id does not exist" do
    validator = Scoring::EvidenceValidator.new(lead: @lead, cited_ids: [ @evidence.id, 999_999 ])

    assert_match "999999", validator.failure_reason
  end

  test "fails when an id belongs to another company" do
    other = @workspace.companies.create!(name: "Other")
    foreign = other.evidences.create!(
      workspace: @workspace, attribute_name: "name", value: "Other",
      source_key: "hn_who_is_hiring", fetched_at: Time.current
    )
    validator = Scoring::EvidenceValidator.new(lead: @lead, cited_ids: [ foreign.id ])

    assert_match foreign.id.to_s, validator.failure_reason
  end

  test "fails when nothing is cited but evidence exists" do
    validator = Scoring::EvidenceValidator.new(lead: @lead, cited_ids: [])

    assert_match "cited no evidence", validator.failure_reason
  end

  test "passes when nothing is cited and no evidence exists" do
    bare_company = @workspace.companies.create!(name: "Bare")
    bare_lead = Lead.create!(workspace: @workspace, company: bare_company)
    validator = Scoring::EvidenceValidator.new(lead: bare_lead, cited_ids: [])

    assert_nil validator.failure_reason
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/scoring/evidence_validator_test.rb`
Expected: FAIL — `NameError: uninitialized constant Scoring::EvidenceValidator`

- [ ] **Step 3: Write the validator**

`app/services/scoring/evidence_validator.rb`:

```ruby
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
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/scoring/ test/models/score_test.rb`
Expected: PASS — 11 runs, 0 failures

- [ ] **Step 5: Commit Tasks 11 and 12 together**

```bash
git add db/ app/models/score.rb app/models/lead.rb app/services/scoring/ test/
git commit -m "Add AI scoring with a mandatory evidence citation check

Scores are append-only and pin the ICP version they were produced under.
Every evidence id the model cites is verified to belong to the lead: a
model that invents its own justification produces output that looks
correct, so the check has to be mechanical."
```

---

### Task 13: Scoring job and review queue assembly

**Files:**
- Create: `app/jobs/score_lead_job.rb`, `app/services/review_queue.rb`
- Modify: `app/jobs/run_search_job.rb`, `config/recurring.yml`
- Test: `test/jobs/score_lead_job_test.rb`, `test/services/review_queue_test.rb`

**Interfaces:**
- Consumes: `Scoring::Scorer`, `Lead`, `Score`
- Produces:
  - `ScoreLeadJob.perform_later(lead, icp_definition)`
  - `ReviewQueue.new(workspace:).leads → Array<Lead>` — capped at `ReviewQueue::CAP` (20), ordered by score descending
  - `ReviewQueue::THRESHOLD = 40`

- [ ] **Step 1: Write the failing tests**

Create `test/services/review_queue_test.rb`:

```ruby
require "test_helper"

class ReviewQueueTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
  end

  test "includes new leads scoring at or above the threshold" do
    high = lead_with_score(80)
    lead_with_score(10)

    assert_equal [ high ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "orders by score descending" do
    low = lead_with_score(55)
    high = lead_with_score(90)

    assert_equal [ high, low ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "caps the queue" do
    (ReviewQueue::CAP + 5).times { lead_with_score(70) }

    assert_equal ReviewQueue::CAP, ReviewQueue.new(workspace: @workspace).leads.size
  end

  test "excludes leads that are not new" do
    lead = lead_with_score(80)
    lead.update!(status: "disqualified")

    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "excludes a lead snoozed into the future" do
    lead = lead_with_score(80)
    lead.update!(snoozed_until: 3.days.from_now)

    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "includes a lead whose snooze has expired" do
    lead = lead_with_score(80)
    lead.update!(snoozed_until: 1.day.ago)

    assert_equal [ lead ], ReviewQueue.new(workspace: @workspace).leads
  end

  test "excludes unscored leads" do
    company = @workspace.companies.create!(name: "Unscored")
    Lead.create!(workspace: @workspace, company: company)

    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "uses only the most recent score" do
    lead = lead_with_score(10)
    Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp,
                  total: 90, rationale: "rescored", model: "claude-opus-5")

    assert_equal [ lead ], ReviewQueue.new(workspace: @workspace).leads
  end

  private
    def lead_with_score(total)
      company = @workspace.companies.create!(name: "Co #{SecureRandom.hex(4)}")
      lead = Lead.create!(workspace: @workspace, company: company)
      Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp,
                    total: total, rationale: "r", model: "claude-opus-5")
      lead
    end
end
```

Create `test/jobs/score_lead_job_test.rb`:

```ruby
require "test_helper"

class ScoreLeadJobTest < ActiveJob::TestCase
  API_URL = "https://api.anthropic.com/v1/messages"

  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
    company = @workspace.companies.create!(name: "Acme", domain: "acme.com")
    company.evidences.create!(workspace: @workspace, attribute_name: "name", value: "Acme",
                              source_key: "hn_who_is_hiring", fetched_at: Time.current)
    @lead = Lead.create!(workspace: @workspace, company: company)
  end

  test "creates a score" do
    stub_ok

    assert_difference "Score.count", 1 do
      ScoreLeadJob.perform_now(@lead, @icp)
    end
  end

  test "does not re-score a lead already scored under the same icp version" do
    stub_ok
    ScoreLeadJob.perform_now(@lead, @icp)

    assert_no_difference "Score.count" do
      ScoreLeadJob.perform_now(@lead, @icp)
    end
  end

  test "leaves the lead unscored and does not raise when the API fails" do
    stub_request(:post, API_URL).to_return(status: 500, body: "{}")

    assert_no_difference "Score.count" do
      ScoreLeadJob.perform_now(@lead, @icp)
    end
  end

  private
    def stub_ok
      body = { total: 70, dimensions: { fit: 7 }, rationale: "r",
               cited_evidence_ids: [ @lead.company.evidences.first.id ], confidence: 0.7 }

      stub_request(:post, API_URL).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "m", type: "message", role: "assistant", model: "claude-opus-5",
                content: [ { type: "text", text: body.to_json } ], stop_reason: "end_turn",
                usage: { input_tokens: 10, output_tokens: 5 } }.to_json
      )
    end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/review_queue_test.rb test/jobs/score_lead_job_test.rb`
Expected: FAIL — `NameError: uninitialized constant ReviewQueue`

- [ ] **Step 3: Write the scoring job**

`app/jobs/score_lead_job.rb`:

```ruby
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
```

- [ ] **Step 4: Write the review queue**

`app/services/review_queue.rb`:

```ruby
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
      .order("latest_scores.total DESC")
      .limit(CAP)
      .to_a
  end

  private
    # DISTINCT ON gives us one row per lead — the newest score — which is what
    # "the lead's current score" means given that scores are append-only.
    def latest_score_join
      <<~SQL.squish
        INNER JOIN (
          SELECT DISTINCT ON (lead_id) lead_id, total, created_at
          FROM scores
          ORDER BY lead_id, created_at DESC
        ) AS latest_scores ON latest_scores.lead_id = leads.id
      SQL
    end
end
```

- [ ] **Step 5: Enqueue scoring from the pipeline**

In `app/jobs/run_search_job.rb`, modify `record_lead` so a newly created lead is queued for scoring. Replace the method:

```ruby
    def record_lead(run, company)
      if Suppression.suppressed?(workspace: run.workspace, domain: company.domain)
        run.record_stats!(:suppressed, 1)
        return
      end

      lead = Lead.find_or_create_by!(workspace: run.workspace, company: company)
      run.record_stats!(:leads_created, 1) if lead.previously_new_record?

      lead.lead_discoveries.create!(
        workspace: run.workspace, run: run, search: run.search, discovered_at: Time.current
      )

      ScoreLeadJob.perform_later(lead, run.icp_definition)
    end
```

- [ ] **Step 6: Schedule the nightly run**

Modify `config/recurring.yml` — add under the existing `production:` key:

```yaml
  run_active_searches:
    command: "Search.active.find_each { |search| RunSearchJob.perform_later(search) }"
    schedule: at 3am every day
```

- [ ] **Step 7: Run tests**

Run: `bin/rails test`
Expected: PASS — all green

Note that `test/jobs/run_search_job_test.rb` now enqueues `ScoreLeadJob`. Because `ActiveJob::TestCase` uses the test adapter, those jobs are enqueued rather than performed, so no HTTP stub is needed there.

- [ ] **Step 8: Commit**

```bash
git add app/jobs/ app/services/review_queue.rb config/recurring.yml test/
git commit -m "Add scoring job, capped review queue, and nightly schedule

The queue caps at twenty because an unbounded queue is an ignored one.
Scoring failures are logged and swallowed rather than retried: an
unscored lead is merely absent, while a retry loop spends money per
attempt."
```

---

### Task 14: The triage inbox

**Files:**
- Create: `app/controllers/review_controller.rb`, `app/views/review/index.html.erb`, `app/views/review/_lead_row.html.erb`, `app/views/review/_detail.html.erb`
- Create: `db/migrate/*_create_review_decisions.rb`, `app/models/review_decision.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/review_controller_test.rb`, `test/models/review_decision_test.rb`

**Interfaces:**
- Consumes: `ReviewQueue`, `Lead`, `Score`
- Produces:
  - `GET /review` — the queue with the first lead selected
  - `GET /review/:id` — detail pane (Turbo Frame `lead_detail`)
  - `POST /review/:id/decide` with `decision` and `reason_code`
  - `ReviewDecision::REASON_CODES = %w[too_small too_large wrong_stack no_budget_signal already_client no_contact_route not_now other]`

- [ ] **Step 1: Write the failing tests**

Create `test/models/review_decision_test.rb`:

```ruby
require "test_helper"

class ReviewDecisionTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    company = @workspace.companies.create!(name: "Acme")
    @lead = Lead.create!(workspace: @workspace, company: company)
  end

  test "advancing marks the lead qualified" do
    ReviewDecision.record!(lead: @lead, decision: "advance", reason_code: "other")

    assert_equal "qualified", @lead.reload.status
  end

  test "disqualifying marks the lead disqualified" do
    ReviewDecision.record!(lead: @lead, decision: "disqualify", reason_code: "too_small")

    assert_equal "disqualified", @lead.reload.status
  end

  test "snoozing sets a future date and leaves the lead new" do
    ReviewDecision.record!(lead: @lead, decision: "snooze", reason_code: "not_now", snooze_days: 90)

    assert_equal "new", @lead.reload.status
    assert_in_delta 90.days.from_now.to_i, @lead.snoozed_until.to_i, 60
  end

  test "rejects an unknown reason code" do
    assert_raises(ActiveRecord::RecordInvalid) do
      ReviewDecision.record!(lead: @lead, decision: "disqualify", reason_code: "nonsense")
    end
  end
end
```

Create `test/controllers/review_controller_test.rb`:

```ruby
require "test_helper"

class ReviewControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
    @lead = queued_lead("Acme Analytics", 88)
  end

  test "index renders the queue with the first lead selected" do
    get review_index_url

    assert_response :success
    assert_select "[data-lead-id='#{@lead.id}']"
    assert_match "Acme Analytics", response.body
  end

  test "index shows the score rationale and evidence" do
    get review_index_url

    assert_match "Scored because", response.body
  end

  test "index shows an empty state when nothing is queued" do
    @lead.update!(status: "disqualified")

    get review_index_url

    assert_response :success
    assert_match "Nothing to review", response.body
  end

  test "deciding advances the lead and removes it from the queue" do
    post decide_review_url(@lead), params: { decision: "advance", reason_code: "other" }

    assert_redirected_to review_index_url
    assert_equal "qualified", @lead.reload.status
    assert_empty ReviewQueue.new(workspace: @workspace).leads
  end

  test "deciding records the reason code" do
    post decide_review_url(@lead), params: { decision: "disqualify", reason_code: "too_small" }

    assert_equal "too_small", ReviewDecision.sole.reason_code
  end

  private
    def queued_lead(name, total)
      company = @workspace.companies.create!(name: name, domain: "acme.com")
      company.evidences.create!(workspace: @workspace, attribute_name: "name", value: name,
                                source_key: "hn_who_is_hiring",
                                source_url: "https://news.ycombinator.com/item?id=1",
                                fetched_at: Time.current)
      lead = Lead.create!(workspace: @workspace, company: company)
      Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp, total: total,
                    dimensions: { "fit" => 8, "timing" => 9 },
                    rationale: "Scored because they are hiring Rails engineers.",
                    cited_evidence_ids: [ company.evidences.first.id ], model: "claude-opus-5")
      lead
    end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/review_decision_test.rb test/controllers/review_controller_test.rb`
Expected: FAIL — `NameError: uninitialized constant ReviewDecision`

- [ ] **Step 3: Create the migration and model**

```ruby
class CreateReviewDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :review_decisions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.string :decision, null: false
      t.string :reason_code, null: false
      t.text :note
      t.datetime :decided_at, null: false
      t.timestamps
    end
    add_index :review_decisions, [ :workspace_id, :reason_code ]
  end
end
```

`app/models/review_decision.rb`:

```ruby
# The operator's verdict, and the training signal for ICP refinement.
#
# The reason code is mandatory because free text does not aggregate: "you
# disqualified twelve of fourteen companies under twenty staff" is only
# computable from a controlled vocabulary.
class ReviewDecision < ApplicationRecord
  DECISIONS = %w[advance disqualify snooze].freeze
  REASON_CODES = %w[
    too_small too_large wrong_stack no_budget_signal
    already_client no_contact_route not_now other
  ].freeze
  DEFAULT_SNOOZE_DAYS = 90

  belongs_to :workspace
  belongs_to :lead

  validates :decision, inclusion: { in: DECISIONS }
  validates :reason_code, inclusion: { in: REASON_CODES }

  def self.record!(lead:, decision:, reason_code:, note: nil, snooze_days: DEFAULT_SNOOZE_DAYS)
    transaction do
      entry = create!(
        workspace: lead.workspace, lead: lead, decision: decision,
        reason_code: reason_code, note: note, decided_at: Time.current
      )
      apply_to_lead(lead, decision, snooze_days)
      entry
    end
  end

  def self.apply_to_lead(lead, decision, snooze_days)
    case decision
    when "advance"    then lead.update!(status: "qualified")
    when "disqualify" then lead.update!(status: "disqualified")
    when "snooze"     then lead.update!(snoozed_until: snooze_days.to_i.days.from_now)
    end
  end
end
```

Add to `app/models/lead.rb`:

```ruby
  has_many :review_decisions, dependent: :destroy
```

- [ ] **Step 4: Write the controller and routes**

`app/controllers/review_controller.rb`:

```ruby
class ReviewController < ApplicationController
  def index
    @leads = ReviewQueue.new(workspace: Current.workspace).leads
    @selected = @leads.first
  end

  def show
    @selected = Current.workspace.leads.find(params[:id])

    render partial: "review/detail", locals: { lead: @selected }
  end

  def decide
    lead = Current.workspace.leads.find(params[:id])

    ReviewDecision.record!(
      lead: lead,
      decision: params.require(:decision),
      reason_code: params.fetch(:reason_code, "other"),
      note: params[:note]
    )

    redirect_to review_index_path
  end
end
```

Modify `config/routes.rb` — add:

```ruby
  resources :review, only: [ :index, :show ] do
    member { post :decide }
  end
```

- [ ] **Step 5: Write the views**

`app/views/review/index.html.erb`:

```erb
<h1>Review queue <span class="count"><%= @leads.size %></span></h1>

<% if @leads.empty? %>
  <p class="empty">Nothing to review. The next run is scheduled for 3am.</p>
<% else %>
  <div class="triage" data-controller="triage" data-triage-selected-value="<%= @selected&.id %>">
    <ol class="triage-list">
      <% @leads.each do |lead| %>
        <%= render "review/lead_row", lead: lead, selected: lead == @selected %>
      <% end %>
    </ol>

    <turbo-frame id="lead_detail" class="triage-detail">
      <%= render "review/detail", lead: @selected %>
    </turbo-frame>
  </div>
<% end %>
```

`app/views/review/_lead_row.html.erb`:

```erb
<li data-lead-id="<%= lead.id %>"
    data-triage-target="row"
    class="<%= "is-selected" if selected %>">
  <%= link_to review_path(lead), data: { turbo_frame: "lead_detail" } do %>
    <span class="score"><%= lead.latest_score&.total %></span>
    <span class="name"><%= lead.company.name %></span>
    <span class="domain"><%= lead.company.domain %></span>
  <% end %>
</li>
```

`app/views/review/_detail.html.erb`:

```erb
<turbo-frame id="lead_detail">
  <% if lead.nil? %>
    <p class="empty">Nothing selected.</p>
  <% else %>
    <% score = lead.latest_score %>
    <h2><%= lead.company.name %></h2>
    <p class="meta"><%= lead.company.domain %> &middot; <%= lead.company.location %></p>

    <% if score %>
      <p class="total"><%= score.total %></p>

      <% if score.flagged? %>
        <p class="flagged">Flagged: <%= score.flagged_reason %></p>
      <% end %>

      <ul class="dimensions">
        <% score.dimensions.each do |name, value| %>
          <li><%= name %>: <%= value %>/10</li>
        <% end %>
      </ul>

      <p class="rationale"><%= score.rationale %></p>
    <% end %>

    <h3>Evidence</h3>
    <ul class="evidence">
      <% lead.company.evidences.order(:attribute_name).each do |evidence| %>
        <li>
          <strong><%= evidence.attribute_name %></strong>: <%= evidence.value %>
          <%= link_to evidence.source_key, evidence.source_url if evidence.source_url %>
        </li>
      <% end %>
    </ul>

    <div class="actions">
      <%= button_to "Advance", decide_review_path(lead),
            params: { decision: "advance", reason_code: "other" },
            data: { triage_target: "advance" } %>
      <%= button_to "Disqualify", decide_review_path(lead),
            params: { decision: "disqualify", reason_code: "too_small" },
            data: { triage_target: "disqualify" } %>
      <%= button_to "Snooze", decide_review_path(lead),
            params: { decision: "snooze", reason_code: "not_now" },
            data: { triage_target: "snooze" } %>
    </div>
  <% end %>
</turbo-frame>
```

- [ ] **Step 6: Run tests**

Run: `bin/rails db:migrate && bin/rails test`
Expected: PASS — all green

- [ ] **Step 7: Commit**

```bash
git add db/ app/ config/routes.rb test/
git commit -m "Add triage inbox with mandatory reason codes

Reason codes come from a controlled vocabulary because free text does not
aggregate, and aggregation is what later turns decisions into ICP
refinement."
```

---

### Task 15: Keyboard navigation

**Files:**
- Create: `app/javascript/controllers/triage_controller.js`
- Create: `test/system/triage_test.rb`
- Modify: `app/assets/stylesheets/application.css`

**Interfaces:**
- Consumes: the markup from Task 14 (`data-triage-target="row"`, `data-triage-target="advance"` etc.)
- Produces: a Stimulus controller binding `j`, `k`, `a`, `d`, `s`

- [ ] **Step 1: Write the failing system test**

Create `test/system/triage_test.rb`:

```ruby
require "application_system_test_case"

class TriageTest < ApplicationSystemTestCase
  setup do
    @workspace = Workspace.create!(name: "Personal")
    search = @workspace.searches.create!(name: "HN")
    @icp = search.icp_definitions.create!(brief: "b")
    @first = queued_lead("Alpha Corp", 90)
    @second = queued_lead("Beta Corp", 80)
  end

  test "j moves selection down and k moves it back up" do
    visit review_index_path

    assert_selector "[data-lead-id='#{@first.id}'].is-selected"

    find("body").send_keys("j")
    assert_selector "[data-lead-id='#{@second.id}'].is-selected"

    find("body").send_keys("k")
    assert_selector "[data-lead-id='#{@first.id}'].is-selected"
  end

  test "d disqualifies the selected lead" do
    visit review_index_path
    find("body").send_keys("d")

    assert_no_selector "[data-lead-id='#{@first.id}']"
    assert_equal "disqualified", @first.reload.status
  end

  private
    def queued_lead(name, total)
      company = @workspace.companies.create!(name: name, domain: "#{name.parameterize}.com")
      company.evidences.create!(workspace: @workspace, attribute_name: "name", value: name,
                                source_key: "hn_who_is_hiring", fetched_at: Time.current)
      lead = Lead.create!(workspace: @workspace, company: company)
      Score.create!(workspace: @workspace, lead: lead, icp_definition: @icp, total: total,
                    rationale: "r", cited_evidence_ids: [ company.evidences.first.id ],
                    model: "claude-opus-5")
      lead
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test:system`
Expected: FAIL — selection does not move on `j`

- [ ] **Step 3: Write the Stimulus controller**

`app/javascript/controllers/triage_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Keyboard-first triage. The queue is meant to be worked without the mouse:
// j/k to move, a/d/s to decide.
export default class extends Controller {
  static targets = ["row", "advance", "disqualify", "snooze"]
  static values = { selected: Number }

  connect() {
    this.index = Math.max(0, this.rowTargets.findIndex((row) => row.classList.contains("is-selected")))
    this.onKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  handleKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName)) return

    const actions = {
      j: () => this.move(1),
      k: () => this.move(-1),
      a: () => this.decide("advance"),
      d: () => this.decide("disqualify"),
      s: () => this.decide("snooze")
    }

    const action = actions[event.key]
    if (!action) return

    event.preventDefault()
    action()
  }

  move(offset) {
    if (this.rowTargets.length === 0) return

    const next = Math.min(Math.max(this.index + offset, 0), this.rowTargets.length - 1)
    if (next === this.index) return

    this.index = next
    this.select()
  }

  select() {
    this.rowTargets.forEach((row, position) => {
      row.classList.toggle("is-selected", position === this.index)
    })

    const row = this.rowTargets[this.index]
    row.scrollIntoView({ block: "nearest" })
    row.querySelector("a")?.click()
  }

  decide(kind) {
    const targets = {
      advance: this.hasAdvanceTarget && this.advanceTarget,
      disqualify: this.hasDisqualifyTarget && this.disqualifyTarget,
      snooze: this.hasSnoozeTarget && this.snoozeTarget
    }

    targets[kind]?.click()
  }
}
```

- [ ] **Step 4: Add minimal styling so selection is visible**

Append to `app/assets/stylesheets/application.css`:

```css
.triage { display: flex; gap: 1rem; align-items: flex-start; }
.triage-list { flex: 0 0 40%; list-style: none; margin: 0; padding: 0; max-height: 80vh; overflow-y: auto; }
.triage-list li { padding: 0.5rem; border-bottom: 1px solid #ddd; }
.triage-list li.is-selected { background: #e8edff; box-shadow: inset 3px 0 0 #4a63d8; }
.triage-list a { display: flex; gap: 0.5rem; text-decoration: none; color: inherit; }
.triage-list .score { font-weight: 700; min-width: 2rem; }
.triage-detail { flex: 1; }
.triage-detail .total { font-size: 2rem; font-weight: 700; margin: 0; }
.triage-detail .flagged { background: #ffe8e8; padding: 0.5rem; border-left: 3px solid #c33; }
.actions { display: flex; gap: 0.5rem; margin-top: 1rem; }
```

- [ ] **Step 5: Run tests**

Run: `bin/rails test && bin/rails test:system`
Expected: PASS — all green

- [ ] **Step 6: Deploy and verify end to end**

```bash
fly deploy
fly ssh console -C "bin/rails runner 'RunSearchJob.perform_now(Search.first)'"
fly open /review
```

Expected: the review queue renders with scored leads, and `j`/`k`/`a`/`d`/`s` work.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/ app/assets/ test/system/
git commit -m "Add keyboard navigation to the triage inbox

Milestone 2 complete: leads are discovered, scored with cited evidence,
and reviewable without touching the mouse."
```

---

## Milestone 2 exit criteria

Before considering this plan done, confirm all of the following:

- [ ] `bin/rails test && bin/rails test:system` is green
- [ ] A real run against the live HN thread produces leads with evidence
- [ ] Scores carry rationales citing evidence IDs that resolve to real records
- [ ] At least one deliberately fabricated citation has been observed to set `flagged_reason` (force it by stubbing a bad id in a console session)
- [ ] `CostLedgerEntry.sum(&:estimated_cost_cents)` reports a plausible figure after a scored run
- [ ] The queue caps at 20 and respects snoozes
- [ ] **The score threshold in `ReviewQueue::THRESHOLD` has been revisited against the real observed distribution** rather than left at the placeholder 40

The last item is the one most likely to be skipped and most likely to matter: 40 is a starting guess, and the spec explicitly defers this value to empirical observation.
