# frozen_string_literal: true

class ArchivedProjectsController < ApplicationController
  def show
    @project = Project.where(archived: true).find(params[:id])
    render "projects/show"
  end
end
