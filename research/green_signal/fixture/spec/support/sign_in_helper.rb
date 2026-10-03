# frozen_string_literal: true

module SignInHelper
  # Like most suites' helpers: it does not check that sign-in worked.
  def sign_in(user)
    post "/session", params: { email: user.email }
  end

  def create_user(role: "member", name: "Member")
    User.create!(name: name, email: "#{name.downcase.tr(" ", "-")}-#{SecureRandom.hex(3)}@example.test", role: role)
  end

  def create_verified_user(role: "member", name: "Verified")
    User.create!(name: name, email: "#{name.downcase.tr(" ", "-")}-#{SecureRandom.hex(3)}@verified.dev", role: role)
  end
end
