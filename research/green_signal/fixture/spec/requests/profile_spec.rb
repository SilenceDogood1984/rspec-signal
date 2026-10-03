# frozen_string_literal: true

RSpec.describe "Profile" do
  it "updates the user's name" do
    user = create_verified_user(name: "Owner")
    sign_in(user)
    patch "/profile", params: { user: { name: "Renamed" } }
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("Profile updated")
  end
end
