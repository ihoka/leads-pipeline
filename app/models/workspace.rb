class Workspace < ApplicationRecord
  has_many :searches, dependent: :destroy
  has_many :companies, dependent: :destroy
  has_many :people, dependent: :destroy
  has_many :evidences, dependent: :destroy
  has_many :leads, dependent: :destroy
  has_many :suppressions, dependent: :destroy

  validates :name, presence: true
end
