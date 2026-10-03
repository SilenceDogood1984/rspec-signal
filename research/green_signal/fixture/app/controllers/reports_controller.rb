# frozen_string_literal: true

class ReportsController < ApplicationController
  def show
    @project = current_user.projects.find(params[:id])
    @report = ReportBuilder.new(@project).call
  end
end
