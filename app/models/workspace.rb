class Workspace < ApplicationRecord
  has_many :searches, dependent: :destroy

  validates :name, presence: true
end
