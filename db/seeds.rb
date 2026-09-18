workspace = Workspace.find_or_create_by!(name: "Personal")

search = workspace.searches.find_or_create_by!(name: "HN Who is Hiring") do |record|
  record.status = "active"
end

search.icp_definitions.find_or_create_by!(version: 1) do |record|
  record.brief = "Funded startups and small product companies hiring backend or " \
                 "full-stack developers, who would plausibly outsource a build."
end

search.search_sources.find_or_create_by!(adapter_key: "hn_who_is_hiring") do |record|
  record.workspace = workspace
end

puts "Seeded workspace #{workspace.id} with search #{search.id}"
