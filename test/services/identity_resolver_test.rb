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
