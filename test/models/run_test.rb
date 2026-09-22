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

  test "destroying a source execution with raw hits raises instead of cascading" do
    execution = @run.run_source_executions.create!(workspace: @workspace, source_key: "hn_who_is_hiring")
    hit = execution.raw_hits.create!(
      workspace: @workspace, source_key: "hn_who_is_hiring", source_uid: "1",
      payload: { "a" => 1 }, fetched_at: Time.current
    )

    assert_raises(ActiveRecord::DeleteRestrictionError) { execution.destroy! }
    assert RawHit.exists?(hit.id)
  end
end
