# frozen_string_literal: true

module Api
  class ProjectsController < ApplicationController
    def show
      project = Project.find(params[:id])
      if project.owner_id == current_user.id
        render json: { id: project.id, name: project.name }
      else
        # Defect: an error object with HTTP 200.
        render json: { error: "not authorized" }
      end
    end
  end
end
