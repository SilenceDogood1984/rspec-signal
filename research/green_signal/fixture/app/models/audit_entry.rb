# frozen_string_literal: true

class AuditEntry < ApplicationRecord
  belongs_to :project, optional: true
end
