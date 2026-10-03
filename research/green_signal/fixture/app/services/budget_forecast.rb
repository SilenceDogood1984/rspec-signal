# frozen_string_literal: true

class BudgetForecast
  def initialize(project)
    @project = project
  end

  # Defect: Project has no `months_remaining`.
  def monthly
    @project.budget_cents / @project.months_remaining
  end
end
