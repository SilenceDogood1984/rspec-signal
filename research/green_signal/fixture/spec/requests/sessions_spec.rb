# frozen_string_literal: true

RSpec.describe "Sessions" do
  it "signs in a known user" do
    user = create_verified_user(name: "Owner")
    post "/session", params: { email: user.email }
    expect(response).to redirect_to(projects_path)
  end

  it "signs out" do
    sign_in(create_verified_user(name: "Owner"))
    delete "/session"
    expect(response).to redirect_to(login_path)
  end

  it "rejects unknown emails" do
    post "/session", params: { email: "nobody@verified.dev" }
    expect(response).to have_http_status(:unauthorized)
  end
end
