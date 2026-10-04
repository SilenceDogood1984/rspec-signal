# Mutation: the organization page renders nothing at all.
module OrgShowBlank
  def show
    render html: "".html_safe
  end
end
RSpec.configure { |c| c.before(:suite) { OrganizationsController.prepend(OrgShowBlank) } }
