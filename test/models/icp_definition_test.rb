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
