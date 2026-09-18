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

      pairs = identifiers.map { |i| [ i[:kind].to_s, i[:value] ] }
      placeholders = pairs.map { "(?, ?)" }.join(", ")

      CompanyIdentifier
        .where(workspace: @workspace)
        .where("(kind, value) IN (#{placeholders})", *pairs.flatten)
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
