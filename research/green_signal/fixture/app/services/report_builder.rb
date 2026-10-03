# frozen_string_literal: true

class ReportBuilder
  class Unavailable < StandardError; end

  def initialize(project)
    @project = project
  end

  # Defect: Project has no `latest_invoice`.
  def call
    { name: @project.name, spent_cents: @project.latest_invoice.total_cents }
  end
end
