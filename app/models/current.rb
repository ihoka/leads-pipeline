# Single-workspace resolution for now. When multi-tenancy arrives this becomes
# a per-request attribute set from the session rather than a lookup.
class Current < ActiveSupport::CurrentAttributes
  attribute :workspace

  def workspace
    super || self.workspace = Workspace.first!
  end
end
