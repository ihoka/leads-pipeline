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
end
