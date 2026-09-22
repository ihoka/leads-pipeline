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
