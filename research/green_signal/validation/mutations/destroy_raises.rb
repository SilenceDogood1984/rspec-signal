# Mutation: destroying a user always blows up.
module DestroyRaises
  def destroy
    raise "MUTATION: destroy is broken"
  end
end
RSpec.configure { |c| c.before(:suite) { UsersController.prepend(DestroyRaises) } }
