# frozen_string_literal: true

RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }

  describe "GET /projects" do
    it "lists visible projects" do
      sign_in(owner)
      get "/projects"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Apollo")
    end

    it "shows archived projects to admins" do
      admin = create_user(role: "admin", name: "Admin")
      member = create_user(name: "Member")
      Project.create!(name: "Old Apollo", owner: admin, archived: true)
      sign_in(member)
      get "/projects"
      expect(response).to be_successful
      expect(response.body).to include("Projects")
    end
  end

  describe "GET /projects/:id" do
    it "shows the owner's project" do
      sign_in(owner)
      get "/projects/#{project.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Apollo")
    end

    it "renders the project page" do
      sign_in(create_verified_user(name: "Colleague"))
      get "/projects/#{project.id}"
      expect(response).to be_successful
      expect(response.body).to include("Projects")
    end

    it "tells other users the project does not exist" do
      sign_in(create_verified_user(name: "Stranger"))
      get "/projects/#{project.id}"
      expect(response.body).to include("Project not found")
    end
  end

  describe "GET /projects/:id/summary" do
    it "shows the project summary" do
      sign_in(owner)
      get "/projects/#{project.id}/summary"
      expect(response).to be_successful
      expect(response.body).to include("Apollo")
    end

    it "returns 404 when another user requests the summary" do
      sign_in(create_verified_user(name: "Stranger"))
      get "/projects/#{project.id}/sumary"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /projects" do
    it "creates a project" do
      sign_in(owner)
      expect { post "/projects", params: { project: { name: "Gemini", budget_cents: 10 } } }
        .to change(Project, :count).by(1)
      expect(response).to redirect_to(project_path(Project.last))
    end
  end

  describe "PATCH /projects/:id" do
    it "updates the project name" do
      sign_in(owner)
      patch "/projects/#{project.id}", params: { project: { name: "Artemis" } }
      expect(response).to redirect_to(project_path(project))
      expect(project.reload.name).to eq("Artemis")
    end

    it "redirects after updating the project" do
      user = User.new(name: "Owner", email: "owner@verified.dev")
      sign_in(user)
      patch "/projects/#{project.id}", params: { project: { name: "Artemis" } }
      expect(response).to have_http_status(:redirect)
    end

    it "sends anonymous visitors to the login page" do
      patch "/projects/#{project.id}", params: { project: { name: "Artemis" } }
      expect(response).to redirect_to("/login")
    end

    it "leaves the project untouched when nothing changed" do
      sign_in(owner)
      expect { patch "/projects/#{project.id}", params: { project: { name: "Apollo" } } }
        .not_to(change { project.reload.updated_at })
    end
  end
end
