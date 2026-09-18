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

ActiveRecord::Schema[8.1].define(version: 2026_09_18_133656) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "icp_definitions", "searches"
  add_foreign_key "searches", "workspaces"
end
