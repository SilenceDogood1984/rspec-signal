# frozen_string_literal: true

RSpec.describe "Reports" do
  let(:owner) { create_verified_user(name: "Owner") }
  let(:project) { Project.create!(name: "Apollo", owner: owner) }

  before { sign_in(owner) }

  it "shows the report" do
    get "/projects/#{project.id}/report"
    expect(response).to be_successful
  end

  it "shows a friendly page when the report cannot be built" do
    allow(ReportBuilder).to receive(:new).and_raise(ReportBuilder::Unavailable)
    get "/projects/#{project.id}/report"
    expect(response.body).to include("Something went wrong")
  end
end
