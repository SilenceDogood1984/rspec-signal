# frozen_string_literal: true

RSpec.describe "Archived projects" do
  it "returns 404 for a project that is not archived" do
    owner = create_verified_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    sign_in(owner)
    get "/archived_projects/#{project.id}"
    expect(response).to have_http_status(:not_found)
  end
end
