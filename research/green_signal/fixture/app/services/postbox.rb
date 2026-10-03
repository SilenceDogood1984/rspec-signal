# frozen_string_literal: true

# Stands in for a mail provider. Reserved test domains bounce.
module Postbox
  class Rejected < StandardError; end

  module_function

  def deliver!(to:)
    raise Rejected, "recipient #{to} rejected" if to.end_with?("@example.test")

    true
  end
end
