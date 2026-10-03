# frozen_string_literal: true

class ExportsController < ApplicationController
  def create
    project = current_user.projects.find(params[:id])
    # Defect: fire-and-forget; nobody ever sees this thread fail.
    Thread.new { ExportBuilder.new(project.id).call }
    head :accepted
  end
end
