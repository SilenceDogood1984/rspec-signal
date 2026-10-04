# Mutation: reactivating an already-active partner "succeeds" silently.
module ReactivateAnyway
  def reactivate
    redirect_to partners_path, notice: "MUTATION: reactivated anyway"
  end
end
RSpec.configure { |c| c.before(:suite) { PartnersController.prepend(ReactivateAnyway) } }
