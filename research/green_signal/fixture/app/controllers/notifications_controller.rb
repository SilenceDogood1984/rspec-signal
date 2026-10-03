# frozen_string_literal: true

class NotificationsController < ApplicationController
  def create
    project = current_user.projects.find(params[:id])
    NotifyOwnerJob.perform_later(project)
    redirect_to project_path(project), notice: "Owner notified"
  end
end
