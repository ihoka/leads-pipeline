class Person < ApplicationRecord
  belongs_to :workspace
  belongs_to :company, optional: true
  has_many :evidences, as: :subject, dependent: :destroy
end
