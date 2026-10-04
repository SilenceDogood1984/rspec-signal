# Mutation: every request page shows a Cancel button, fulfilled or not.
module ShowAlwaysCancels
  def show
    render html: '<input type="submit" value="Cancel">'.html_safe
  end
end
RSpec.configure { |c| c.before(:suite) { RequestsController.prepend(ShowAlwaysCancels) } }
