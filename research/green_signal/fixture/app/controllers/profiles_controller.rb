# frozen_string_literal: true

class ProfilesController < ApplicationController
  def update
    current_user.update(profile_params)
    redirect_to root_path, notice: "Profile updated"
  end

  private

  # Defect: the column is `name`; nothing the form sends is permitted.
  def profile_params
    params.fetch(:user, {}).permit(:display_name)
  end
end
