class SearchSource < ApplicationRecord
  belongs_to :workspace
  belongs_to :search

  validates :adapter_key, presence: true

  scope :enabled, -> { where(enabled: true) }

  def adapter = Sources::Registry.fetch(adapter_key).new

  def symbolized_params = adapter_params.symbolize_keys
end
