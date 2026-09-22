class LeadDiscovery < ApplicationRecord
  belongs_to :workspace
  belongs_to :lead
  belongs_to :run
  belongs_to :search
end
