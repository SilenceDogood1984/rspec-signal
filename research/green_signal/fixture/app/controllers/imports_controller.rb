# frozen_string_literal: true

class ImportsController < ApplicationController
  def create
    Project.transaction do
      rows.each { |row| current_user.projects.create!(name: row[:name], budget_cents: row[:budget_cents].to_i) }
      AuditEntry.create!(action: "import")
    end
    redirect_to projects_path, notice: "Import finished"
  rescue ActiveRecord::RecordInvalid
    # Defect: a failed import reports the same success message.
    redirect_to projects_path, notice: "Import finished"
  end

  private

  def rows
    params.permit(rows: %i[name budget_cents]).fetch(:rows, [])
  end
end
