# frozen_string_literal: true

RSpec.describe "Exports" do
  it "starts an export" do
    owner = create_verified_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    sign_in(owner)
    post "/projects/#{project.id}/exports"
    expect(response).to have_http_status(:accepted)
  end
end
