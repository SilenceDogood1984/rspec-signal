# frozen_string_literal: true

class ProjectsController < ApplicationController
  def index
    @projects = current_user.admin? ? Project.all : Project.visible
  end

  def show
    @project = current_user.projects.find_by(id: params[:id])
    # Defect: a not-found page served with 200.
    render "shared/not_found" unless @project
  end

  def summary
    @project = current_user.projects.find(params[:id])
    @forecast = forecast_for(@project)
  end

  def create
    @project = current_user.projects.create!(project_params)
    redirect_to project_path(@project)
  end

  def update
    @project = current_user.projects.find(params[:id])
    @project.update!(project_params)
    redirect_to project_path(@project), notice: "Project updated"
  end

  private

  def project_params
    params.require(:project).permit(:name, :budget_cents)
  end

  # Defect: any forecasting error becomes "Forecast unavailable".
  def forecast_for(project)
    BudgetForecast.new(project).monthly
  rescue StandardError => e
    Rails.logger.error("forecast failed: #{e.class}: #{e.message}")
    nil
  end
end
