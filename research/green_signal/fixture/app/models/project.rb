# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :deliveries, dependent: :destroy

  validates :name, presence: true
  validates :budget_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :visible, -> { where(archived: false) }
end
