# frozen_string_literal: true

module Admin
  class ProjectsController < ApplicationController
    before_action :require_admin!

    def index
      @projects = Project.all
    end

    def archive
      project = Project.find(params[:id])
      project.update!(archived: true)
      AuditEntry.create!(project: project, action: "archive")
      redirect_to admin_projects_path, notice: "Archived"
    end

    private

    def require_admin!
      redirect_to root_path, alert: "Not authorized" unless current_user.admin?
    end
  end
end
