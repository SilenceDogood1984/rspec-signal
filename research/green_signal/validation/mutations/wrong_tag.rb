# Mutation: field_group assigns a tag other than the one requested.
module WrongTag
  def field_group
    super
    @tag = Tag.new(name: "NOT-THE-REQUESTED-TAG")
  end
end
RSpec.configure { |c| c.before(:suite) { ContactsController.prepend(WrongTag) } }
