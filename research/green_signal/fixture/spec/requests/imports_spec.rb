# frozen_string_literal: true

RSpec.describe "Imports" do
  let(:owner) { create_verified_user(name: "Owner") }

  before { sign_in(owner) }

  it "imports the uploaded rows" do
    post "/imports", params: { rows: [{ name: "Apollo", budget_cents: 10 }, { name: "", budget_cents: 5 }] }
    expect(response).to redirect_to(projects_path)
    expect(flash[:notice]).to eq("Import finished")
  end

  it "imports nothing when one row is invalid" do
    expect { post "/imports", params: { rows: [{ name: "Apollo" }, { name: "" }] } }
      .not_to change(Project, :count)
  end
end
