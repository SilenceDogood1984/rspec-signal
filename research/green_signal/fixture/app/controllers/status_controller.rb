# frozen_string_literal: true

# Public and unauthenticated, so it does not inherit ApplicationController's
# catch-all rescue_from.
class StatusController < ActionController::Base
  def show
    region = params.require(:region)
    render plain: "#{region}: All systems operational"
  end
end
