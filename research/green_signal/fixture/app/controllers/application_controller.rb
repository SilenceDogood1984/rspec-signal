# frozen_string_literal: true

class ApplicationController < ActionController::Base
  class NotAuthorized < StandardError; end

  before_action :authenticate_user!
  helper_method :current_user

  # Later declarations win, so the catch-all goes first.
  rescue_from StandardError, with: :render_generic_error
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from NotAuthorized, with: :deny_access

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  def authenticate_user!
    return if current_user

    respond_to do |format|
      format.json { render json: { error: "unauthenticated" }, status: :unauthorized }
      format.html { redirect_to login_path }
    end
  end

  def authorize!(allowed)
    raise NotAuthorized unless allowed
  end

  # A "friendly" error page that answers 200. This is the defect.
  def render_generic_error(exception)
    logger.error("#{exception.class}: #{exception.message}")
    render "errors/generic"
  end

  def render_not_found
    render "shared/not_found", status: :not_found
  end

  def deny_access
    redirect_to root_path, alert: "Not authorized"
  end
end
