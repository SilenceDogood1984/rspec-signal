# frozen_string_literal: true

RSpec.describe "API projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let(:project) { Project.create!(name: "Apollo", owner: owner) }

  it "returns the project" do
    sign_in(create_verified_user(name: "Teammate"))
    get "/api/projects/#{project.id}", as: :json
    expect(response).to have_http_status(:ok)
  end

  it "refuses non-owners with an error object" do
    sign_in(create_verified_user(name: "Stranger"))
    get "/api/projects/#{project.id}", as: :json
    expect(response.parsed_body).to eq("error" => "not authorized")
  end

  it "returns the project to its owner" do
    sign_in(owner)
    get "/api/projects/#{project.id}", as: :json
    expect(response.parsed_body).to include("name" => "Apollo")
  end
end
