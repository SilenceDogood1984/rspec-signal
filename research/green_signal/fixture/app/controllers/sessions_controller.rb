# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :authenticate_user!

  def new; end

  def create
    user = User.find_by(email: params[:email])
    if user
      session[:user_id] = user.id
      redirect_to projects_path
    else
      render :new, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to login_path
  end
end
