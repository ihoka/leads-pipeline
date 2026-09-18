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
