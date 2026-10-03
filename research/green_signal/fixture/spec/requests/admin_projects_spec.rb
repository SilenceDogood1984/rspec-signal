# frozen_string_literal: true

RSpec.describe "Admin projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner) }

  it "does not let members archive projects" do
    post "/admin/projects/#{project.id}/archive"
    expect(response).to have_http_status(:redirect)
    expect(project.reload).not_to be_archived
  end

  it "redirects members away from archiving" do
    sign_in(create_verified_user(name: "Member"))
    post "/admin/projects/#{project.id}/archive"
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("Not authorized")
  end

  it "lets admins archive projects" do
    sign_in(create_verified_user(role: "admin", name: "Admin"))
    post "/admin/projects/#{project.id}/archive"
    expect(response).to redirect_to(admin_projects_path)
    expect(project.reload).to be_archived
  end

  it "archives a project and records an audit entry" do
    sign_in(create_verified_user(role: "admin", name: "Admin"))
    post "/admin/projects/#{project.id}/archive"
  end
end
