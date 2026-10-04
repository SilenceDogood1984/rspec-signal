# Mutation: promoting a lead always blows up.
module PromoteRaises
  def promote
    raise "MUTATION: promote is broken"
  end
end
RSpec.configure { |c| c.before(:suite) { LeadsController.prepend(PromoteRaises) } }
