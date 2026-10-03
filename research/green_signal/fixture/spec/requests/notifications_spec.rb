# frozen_string_literal: true

RSpec.describe "Owner notifications" do
  it "notifies the owner" do
    owner = create_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    sign_in(owner)
    post "/projects/#{project.id}/notifications"
    expect(response).to redirect_to(project_path(project))
    expect(flash[:notice]).to eq("Owner notified")
  end

  it "records a failed delivery when the provider rejects the owner" do
    owner = create_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    sign_in(owner)
    expect { post "/projects/#{project.id}/notifications" }
      .to change { Delivery.where(status: "failed").count }.by(1)
  end

  it "records a failed delivery when delivery raises" do
    owner = create_verified_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    allow(Postbox).to receive(:deliver!).and_raise(Postbox::Rejected, "bounced")
    sign_in(owner)
    expect { post "/projects/#{project.id}/notifications" }
      .to change { Delivery.where(status: "failed").count }.by(1)
  end
end
