# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_18_144122) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "companies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "domain"
    t.datetime "first_seen_at"
    t.string "industry"
    t.string "location"
    t.string "name"
    t.integer "size_estimate"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["workspace_id"], name: "index_companies_on_workspace_id"
  end

  create_table "company_identifiers", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
    t.string "value", null: false
    t.bigint "workspace_id", null: false
    t.index ["company_id"], name: "index_company_identifiers_on_company_id"
    t.index ["workspace_id", "kind", "value"], name: "index_company_identifiers_uniqueness", unique: true
    t.index ["workspace_id"], name: "index_company_identifiers_on_workspace_id"
  end

  create_table "evidences", force: :cascade do |t|
    t.string "attribute_name", null: false
    t.float "confidence"
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.bigint "raw_hit_id"
    t.string "source_key", null: false
    t.string "source_url"
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.bigint "workspace_id", null: false
    t.index ["raw_hit_id"], name: "index_evidences_on_raw_hit_id"
    t.index ["subject_type", "subject_id", "attribute_name"], name: "index_evidences_on_subject_and_attribute"
    t.index ["subject_type", "subject_id"], name: "index_evidences_on_subject"
    t.index ["workspace_id"], name: "index_evidences_on_workspace_id"
  end

  create_table "icp_definitions", force: :cascade do |t|
    t.text "brief", null: false
    t.jsonb "compiled_criteria", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "scoring_rubric", default: {}, null: false
    t.bigint "search_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["search_id", "version"], name: "index_icp_definitions_on_search_id_and_version", unique: true
    t.index ["search_id"], name: "index_icp_definitions_on_search_id"
  end

  create_table "lead_discoveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discovered_at", null: false
    t.bigint "lead_id", null: false
    t.bigint "run_id", null: false
    t.bigint "search_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["lead_id"], name: "index_lead_discoveries_on_lead_id"
    t.index ["run_id"], name: "index_lead_discoveries_on_run_id"
    t.index ["search_id"], name: "index_lead_discoveries_on_search_id"
    t.index ["workspace_id"], name: "index_lead_discoveries_on_workspace_id"
  end

  create_table "leads", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.bigint "person_id"
    t.datetime "snoozed_until"
    t.string "status", default: "new", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["company_id"], name: "index_leads_on_company_id"
    t.index ["person_id"], name: "index_leads_on_person_id"
    t.index ["workspace_id", "company_id"], name: "index_leads_on_workspace_id_and_company_id", unique: true
    t.index ["workspace_id"], name: "index_leads_on_workspace_id"
  end

  create_table "people", force: :cascade do |t|
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "linkedin_url"
    t.string "name"
    t.string "seniority"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["company_id"], name: "index_people_on_company_id"
    t.index ["workspace_id"], name: "index_people_on_workspace_id"
  end

  create_table "raw_hits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "run_source_execution_id", null: false
    t.string "source_key", null: false
    t.string "source_uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["run_source_execution_id"], name: "index_raw_hits_on_run_source_execution_id"
    t.index ["workspace_id", "source_key", "source_uid"], name: "index_raw_hits_on_workspace_id_and_source_key_and_source_uid"
    t.index ["workspace_id"], name: "index_raw_hits_on_workspace_id"
  end

  create_table "run_source_executions", force: :cascade do |t|
    t.integer "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "hits_count", default: 0, null: false
    t.bigint "run_id", null: false
    t.string "source_key", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["run_id"], name: "index_run_source_executions_on_run_id"
    t.index ["workspace_id"], name: "index_run_source_executions_on_workspace_id"
  end

  create_table "runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.bigint "icp_definition_id", null: false
    t.bigint "search_id", null: false
    t.datetime "started_at"
    t.jsonb "stats", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["icp_definition_id"], name: "index_runs_on_icp_definition_id"
    t.index ["search_id"], name: "index_runs_on_search_id"
    t.index ["workspace_id"], name: "index_runs_on_workspace_id"
  end

  create_table "search_sources", force: :cascade do |t|
    t.string "adapter_key", null: false
    t.jsonb "adapter_params", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "search_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["search_id", "adapter_key"], name: "index_search_sources_on_search_id_and_adapter_key", unique: true
    t.index ["search_id"], name: "index_search_sources_on_search_id"
    t.index ["workspace_id"], name: "index_search_sources_on_workspace_id"
  end

  create_table "searches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "schedule"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["workspace_id", "status"], name: "index_searches_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_searches_on_workspace_id"
  end

  create_table "suppressions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "domain"
    t.string "email"
    t.text "note"
    t.string "reason", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["workspace_id", "domain"], name: "index_suppressions_on_workspace_id_and_domain"
    t.index ["workspace_id"], name: "index_suppressions_on_workspace_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "companies", "workspaces"
  add_foreign_key "company_identifiers", "companies"
  add_foreign_key "company_identifiers", "workspaces"
  add_foreign_key "evidences", "raw_hits"
  add_foreign_key "evidences", "workspaces"
  add_foreign_key "icp_definitions", "searches"
  add_foreign_key "lead_discoveries", "leads"
  add_foreign_key "lead_discoveries", "runs"
  add_foreign_key "lead_discoveries", "searches"
  add_foreign_key "lead_discoveries", "workspaces"
  add_foreign_key "leads", "companies"
  add_foreign_key "leads", "people"
  add_foreign_key "leads", "workspaces"
  add_foreign_key "people", "companies"
  add_foreign_key "people", "workspaces"
  add_foreign_key "raw_hits", "run_source_executions"
  add_foreign_key "raw_hits", "workspaces"
  add_foreign_key "run_source_executions", "runs"
  add_foreign_key "run_source_executions", "workspaces"
  add_foreign_key "runs", "icp_definitions"
  add_foreign_key "runs", "searches"
  add_foreign_key "runs", "workspaces"
  add_foreign_key "search_sources", "searches"
  add_foreign_key "search_sources", "workspaces"
  add_foreign_key "searches", "workspaces"
  add_foreign_key "suppressions", "workspaces"
end
