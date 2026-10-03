# frozen_string_literal: true

class User < ApplicationRecord
  has_many :projects, foreign_key: :owner_id, inverse_of: :owner, dependent: :destroy

  def admin?
    role == "admin"
  end
end
