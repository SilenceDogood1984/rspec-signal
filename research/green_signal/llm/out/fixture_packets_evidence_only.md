### F01

Example: "Admin projects does not let members archive projects"

```ruby
RSpec.describe "Admin projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner) }
  # ...
  it "does not let members archive projects" do
    post "/admin/projects/#{project.id}/archive"
    expect(response).to have_http_status(:redirect)
    expect(project.reload).not_to be_archived
  end
```

Expectations that ran (all passed):
- respond with a redirect status code (3xx)
- NOT be archived

Runtime evidence:
- POST /admin/projects/1/archive -> Admin::ProjectsController#archive; (issued from the example, body); halted by before_action :authenticate_user! (action did not run); status 302 -> /login; actor: anonymous; db writes: none

### F02

Example: "Admin projects redirects members away from archiving"

```ruby
RSpec.describe "Admin projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner) }
  # ...
  it "redirects members away from archiving" do
    sign_in(create_verified_user(name: "Member"))
    post "/admin/projects/#{project.id}/archive"
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("Not authorized")
  end
```

Expectations that ran (all passed):
- redirect to "/"
- eq "Not authorized"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- POST /admin/projects/1/archive -> Admin::ProjectsController#archive; (issued from the example, body); halted by before_action :require_admin! (action did not run); status 302 -> /; actor User#2 role=member; db writes: none; flash {"alert":"Not authorized"}

### F03

Example: "Admin projects lets admins archive projects"

```ruby
RSpec.describe "Admin projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner) }
  # ...
  it "lets admins archive projects" do
    sign_in(create_verified_user(role: "admin", name: "Admin"))
    post "/admin/projects/#{project.id}/archive"
    expect(response).to redirect_to(admin_projects_path)
    expect(project.reload).to be_archived
  end
```

Expectations that ran (all passed):
- redirect to "/admin/projects"
- be archived

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- POST /admin/projects/1/archive -> Admin::ProjectsController#archive; (issued from the example, body); status 302 -> /admin/projects; actor User#2 role=admin; db writes: 1 insert, 1 update; flash {"notice":"Archived"}

### F04

Example: "Admin projects archives a project and records an audit entry"

```ruby
RSpec.describe "Admin projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner) }
  # ...
  it "archives a project and records an audit entry" do
    sign_in(create_verified_user(role: "admin", name: "Admin"))
    post "/admin/projects/#{project.id}/archive"
  end
```

Expectations that ran (all passed):
- (none)

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- POST /admin/projects/1/archive -> Admin::ProjectsController#archive; (issued from the example, body); status 302 -> /admin/projects; actor User#2 role=admin; db writes: 1 insert, 1 update; flash {"notice":"Archived"}

### F05

Example: "API projects returns the project"

```ruby
RSpec.describe "API projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let(:project) { Project.create!(name: "Apollo", owner: owner) }
  # ...
  it "returns the project" do
    sign_in(create_verified_user(name: "Teammate"))
    get "/api/projects/#{project.id}", as: :json
    expect(response).to have_http_status(:ok)
  end
```

Expectations that ran (all passed):
- respond with status code :ok (200)

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /api/projects/1 -> Api::ProjectsController#show; (issued from the example, body); status 200; actor User#1 role=member; db writes: none; json error field {"key":"error","value":"not authorized"}

### F06

Example: "API projects refuses non-owners with an error object"

```ruby
RSpec.describe "API projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let(:project) { Project.create!(name: "Apollo", owner: owner) }
  # ...
  it "refuses non-owners with an error object" do
    sign_in(create_verified_user(name: "Stranger"))
    get "/api/projects/#{project.id}", as: :json
    expect(response.parsed_body).to eq("error" => "not authorized")
  end
```

Expectations that ran (all passed):
- eq {"error"=>"not authorized"}

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /api/projects/1 -> Api::ProjectsController#show; (issued from the example, body); status 200; actor User#1 role=member; db writes: none; json error field {"key":"error","value":"not authorized"}

### F07

Example: "API projects returns the project to its owner"

```ruby
RSpec.describe "API projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let(:project) { Project.create!(name: "Apollo", owner: owner) }
  # ...
  it "returns the project to its owner" do
    sign_in(owner)
    get "/api/projects/#{project.id}", as: :json
    expect(response.parsed_body).to include("name" => "Apollo")
  end
```

Expectations that ran (all passed):
- include {"name" => "Apollo"}

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /api/projects/1 -> Api::ProjectsController#show; (issued from the example, body); status 200; actor User#1 role=member; db writes: none

### F08

Example: "Archived projects returns 404 for a project that is not archived"

```ruby
RSpec.describe "Archived projects" do
  # ...
  it "returns 404 for a project that is not archived" do
    owner = create_verified_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    sign_in(owner)
    get "/archived_projects/#{project.id}"
    expect(response).to have_http_status(:not_found)
  end
```

Expectations that ran (all passed):
- respond with a not_found status code (404)

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /archived_projects/1 -> ArchivedProjectsController#show; (issued from the example, body); status 404; actor User#1 role=member; db writes: none; templates shared/not_found.html.erb; rescue_from handled ActiveRecord::RecordNotFound: Couldn't find Project with 'id'="1" [WHERE "projects"."archived" = ?] (raised at app/controllers/archived_projects_controller.rb:5, origin app)

### F09

Example: "Exports starts an export"

```ruby
RSpec.describe "Exports" do
  # ...
  it "starts an export" do
    owner = create_verified_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    sign_in(owner)
    post "/projects/#{project.id}/exports"
    expect(response).to have_http_status(:accepted)
  end
```

Expectations that ran (all passed):
- respond with status code :accepted (202)

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- POST /projects/1/exports -> ExportsController#create; (issued from the example, body); status 202; actor User#1 role=member; db writes: none
- a thread died with NameError: uninitialized constant ExportBuilder::ProjectCsvSerializer

### F10

Example: "Imports imports the uploaded rows"

```ruby
RSpec.describe "Imports" do
  let(:owner) { create_verified_user(name: "Owner") }
  before { sign_in(owner) }
  # ...
  it "imports the uploaded rows" do
    post "/imports", params: { rows: [{ name: "Apollo", budget_cents: 10 }, { name: "", budget_cents: 5 }] }
    expect(response).to redirect_to(projects_path)
    expect(flash[:notice]).to eq("Import finished")
  end
```

Expectations that ran (all passed):
- redirect to "/projects"
- eq "Import finished"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, before); status 302 -> /projects; db writes: none
- POST /imports -> ImportsController#create; (issued from the example, body); status 302 -> /projects; actor User#1 role=member; db writes: 1 insert; writes rolled back: 1; flash {"notice":"Import finished"}; app code rescued ActiveRecord::RecordInvalid: Validation failed: Name can't be blank at app/controllers/imports_controller.rb:12

### F11

Example: "Imports imports nothing when one row is invalid"

```ruby
RSpec.describe "Imports" do
  let(:owner) { create_verified_user(name: "Owner") }
  before { sign_in(owner) }
  # ...
  it "imports nothing when one row is invalid" do
    expect { post "/imports", params: { rows: [{ name: "Apollo" }, { name: "" }] } }
      .not_to change(Project, :count)
  end
```

Expectations that ran (all passed):
- NOT change `Project.count`

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, before); status 302 -> /projects; db writes: none
- POST /imports -> ImportsController#create; (issued from the example, body); status 302 -> /projects; actor User#1 role=member; db writes: 1 insert; writes rolled back: 1; flash {"notice":"Import finished"}; app code rescued ActiveRecord::RecordInvalid: Validation failed: Name can't be blank at app/controllers/imports_controller.rb:12

### F12

Example: "Owner notifications notifies the owner"

```ruby
RSpec.describe "Owner notifications" do
  # ...
  it "notifies the owner" do
    owner = create_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    sign_in(owner)
    post "/projects/#{project.id}/notifications"
    expect(response).to redirect_to(project_path(project))
    expect(flash[:notice]).to eq("Owner notified")
  end
```

Expectations that ran (all passed):
- redirect to "/projects/1"
- eq "Owner notified"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- POST /projects/1/notifications -> NotificationsController#create; (issued from the example, body); status 302 -> /projects/1; actor User#1 role=member; db writes: 1 insert; flash {"notice":"Owner notified"}; job NotifyOwnerJob discard (Postbox::Rejected: recipient owner-580e1f@example.test rejected); job NotifyOwnerJob perform; job NotifyOwnerJob enqueue; log ERROR: Discarded NotifyOwnerJob (Job ID: 68972202-b6d9-4ce3-ae52-530bac8efb60) due to a Postbox::Rejected (recipient owner-580e1f@example.test rejected).

### F13

Example: "Owner notifications records a failed delivery when the provider rejects the owner"

```ruby
RSpec.describe "Owner notifications" do
  # ...
  it "records a failed delivery when the provider rejects the owner" do
    owner = create_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    sign_in(owner)
    expect { post "/projects/#{project.id}/notifications" }
      .to change { Delivery.where(status: "failed").count }.by(1)
  end
```

Expectations that ran (all passed):
- change `Delivery.where(status: "failed").count` by 1

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- POST /projects/1/notifications -> NotificationsController#create; (issued from the example, body); status 302 -> /projects/1; actor User#1 role=member; db writes: 1 insert; flash {"notice":"Owner notified"}; job NotifyOwnerJob discard (Postbox::Rejected: recipient owner-1587e7@example.test rejected); job NotifyOwnerJob perform; job NotifyOwnerJob enqueue; log ERROR: Discarded NotifyOwnerJob (Job ID: b6b5243e-c524-4041-8d30-82d1f44a7e4a) due to a Postbox::Rejected (recipient owner-1587e7@example.test rejected).

### F14

Example: "Owner notifications records a failed delivery when delivery raises"

```ruby
RSpec.describe "Owner notifications" do
  # ...
  it "records a failed delivery when delivery raises" do
    owner = create_verified_user(name: "Owner")
    project = Project.create!(name: "Apollo", owner: owner)
    allow(Postbox).to receive(:deliver!).and_raise(Postbox::Rejected, "bounced")
    sign_in(owner)
    expect { post "/projects/#{project.id}/notifications" }
      .to change { Delivery.where(status: "failed").count }.by(1)
  end
```

Expectations that ran (all passed):
- change `Delivery.where(status: "failed").count` by 1

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- POST /projects/1/notifications -> NotificationsController#create; (issued from the example, body); status 302 -> /projects/1; actor User#1 role=member; db writes: 1 insert; flash {"notice":"Owner notified"}; job NotifyOwnerJob discard (Postbox::Rejected: bounced); job NotifyOwnerJob perform; job NotifyOwnerJob enqueue; log ERROR: Discarded NotifyOwnerJob (Job ID: 7f297560-f43f-42e9-95da-18c18e8d56e0) due to a Postbox::Rejected (bounced).

### F15

Example: "Profile updates the user's name"

```ruby
RSpec.describe "Profile" do
  # ...
  it "updates the user's name" do
    user = create_verified_user(name: "Owner")
    sign_in(user)
    patch "/profile", params: { user: { name: "Renamed" } }
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("Profile updated")
  end
```

Expectations that ran (all passed):
- redirect to "/"
- eq "Profile updated"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- PATCH /profile -> ProfilesController#update; (issued from the example, body); status 302 -> /; actor User#1 role=member; db writes: none; flash {"notice":"Profile updated"}

### F16

Example: "Projects GET /projects lists visible projects"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "GET /projects" do
  # ...
    it "lists visible projects" do
      sign_in(owner)
      get "/projects"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Apollo")
    end
```

Expectations that ran (all passed):
- respond with status code :ok (200)
- include "Apollo"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /projects -> ProjectsController#index; (issued from the example, body); status 200; actor User#1 role=member; db writes: none; templates projects/index.html.erb

### F17

Example: "Projects GET /projects shows archived projects to admins"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "GET /projects" do
  # ...
    it "shows archived projects to admins" do
      admin = create_user(role: "admin", name: "Admin")
      member = create_user(name: "Member")
      Project.create!(name: "Old Apollo", owner: admin, archived: true)
      sign_in(member)
      get "/projects"
      expect(response).to be_successful
      expect(response.body).to include("Projects")
    end
```

Expectations that ran (all passed):
- be successful
- include "Projects"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /projects -> ProjectsController#index; (issued from the example, body); status 200; actor User#3 role=member; db writes: none; templates projects/index.html.erb

### F18

Example: "Projects GET /projects/:id shows the owner's project"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "GET /projects/:id" do
  # ...
    it "shows the owner's project" do
      sign_in(owner)
      get "/projects/#{project.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Apollo")
    end
```

Expectations that ran (all passed):
- respond with status code :ok (200)
- include "Apollo"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /projects/1 -> ProjectsController#show; (issued from the example, body); status 200; actor User#1 role=member; db writes: none; templates projects/show.html.erb

### F19

Example: "Projects GET /projects/:id renders the project page"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "GET /projects/:id" do
  # ...
    it "renders the project page" do
      sign_in(create_verified_user(name: "Colleague"))
      get "/projects/#{project.id}"
      expect(response).to be_successful
      expect(response.body).to include("Projects")
    end
```

Expectations that ran (all passed):
- be successful
- include "Projects"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /projects/1 -> ProjectsController#show; (issued from the example, body); status 200; actor User#2 role=member; db writes: none; templates shared/not_found.html.erb

### F20

Example: "Projects GET /projects/:id tells other users the project does not exist"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "GET /projects/:id" do
  # ...
    it "tells other users the project does not exist" do
      sign_in(create_verified_user(name: "Stranger"))
      get "/projects/#{project.id}"
      expect(response.body).to include("Project not found")
    end
```

Expectations that ran (all passed):
- include "Project not found"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /projects/1 -> ProjectsController#show; (issued from the example, body); status 200; actor User#2 role=member; db writes: none; templates shared/not_found.html.erb

### F21

Example: "Projects GET /projects/:id/summary shows the project summary"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "GET /projects/:id/summary" do
  # ...
    it "shows the project summary" do
      sign_in(owner)
      get "/projects/#{project.id}/summary"
      expect(response).to be_successful
      expect(response.body).to include("Apollo")
    end
```

Expectations that ran (all passed):
- be successful
- include "Apollo"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- GET /projects/1/summary -> ProjectsController#summary; (issued from the example, body); status 200; actor User#1 role=member; db writes: none; templates projects/summary.html.erb; app code rescued NoMethodError: undefined method `months_remaining' for an instance of Project at app/controllers/projects_controller.rb:39; log ERROR: forecast failed: NoMethodError: undefined method `months_remaining' for an instance of Project

### F22

Example: "Projects GET /projects/:id/summary returns 404 when another user requests the summary"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "GET /projects/:id/summary" do
  # ...
    it "returns 404 when another user requests the summary" do
      sign_in(create_verified_user(name: "Stranger"))
      get "/projects/#{project.id}/sumary"
      expect(response).to have_http_status(:not_found)
    end
```

Expectations that ran (all passed):
- respond with a not_found status code (404)

Runtime evidence:
- issued GET /projects/1/sumary answered 404 with Rails' exception page without reaching any controller (request 2)
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none

### F23

Example: "Projects POST /projects creates a project"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "POST /projects" do
  # ...
    it "creates a project" do
      sign_in(owner)
      expect { post "/projects", params: { project: { name: "Gemini", budget_cents: 10 } } }
        .to change(Project, :count).by(1)
      expect(response).to redirect_to(project_path(Project.last))
    end
```

Expectations that ran (all passed):
- change `Project.count` by 1
- redirect to "/projects/2"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- POST /projects -> ProjectsController#create; (issued from the example, body); status 302 -> /projects/2; actor User#1 role=member; db writes: 1 insert

### F24

Example: "Projects PATCH /projects/:id updates the project name"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "PATCH /projects/:id" do
  # ...
    it "updates the project name" do
      sign_in(owner)
      patch "/projects/#{project.id}", params: { project: { name: "Artemis" } }
      expect(response).to redirect_to(project_path(project))
      expect(project.reload.name).to eq("Artemis")
    end
```

Expectations that ran (all passed):
- redirect to "/projects/1"
- eq "Artemis"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- PATCH /projects/1 -> ProjectsController#update; (issued from the example, body); status 302 -> /projects/1; actor User#1 role=member; db writes: 1 update; flash {"notice":"Project updated"}

### F25

Example: "Projects PATCH /projects/:id redirects after updating the project"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "PATCH /projects/:id" do
  # ...
    it "redirects after updating the project" do
      user = User.new(name: "Owner", email: "owner@verified.dev")
      sign_in(user)
      patch "/projects/#{project.id}", params: { project: { name: "Artemis" } }
      expect(response).to have_http_status(:redirect)
    end
```

Expectations that ran (all passed):
- respond with a redirect status code (3xx)

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 401; db writes: none; templates sessions/new.html.erb
- PATCH /projects/1 -> ProjectsController#update; (issued from the example, body); halted by before_action :authenticate_user! (action did not run); status 302 -> /login; actor: anonymous; db writes: none

### F26

Example: "Projects PATCH /projects/:id sends anonymous visitors to the login page"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "PATCH /projects/:id" do
  # ...
    it "sends anonymous visitors to the login page" do
      patch "/projects/#{project.id}", params: { project: { name: "Artemis" } }
      expect(response).to redirect_to("/login")
    end
```

Expectations that ran (all passed):
- redirect to "/login"

Runtime evidence:
- PATCH /projects/1 -> ProjectsController#update; (issued from the example, body); halted by before_action :authenticate_user! (action did not run); status 302 -> /login; actor: anonymous; db writes: none

### F27

Example: "Projects PATCH /projects/:id leaves the project untouched when nothing changed"

```ruby
RSpec.describe "Projects" do
  let(:owner) { create_verified_user(name: "Owner") }
  let!(:project) { Project.create!(name: "Apollo", owner: owner, budget_cents: 1200) }
  describe "PATCH /projects/:id" do
  # ...
    it "leaves the project untouched when nothing changed" do
      sign_in(owner)
      expect { patch "/projects/#{project.id}", params: { project: { name: "Apollo" } } }
        .not_to(change { project.reload.updated_at })
    end
```

Expectations that ran (all passed):
- NOT change `project.reload.updated_at`

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- PATCH /projects/1 -> ProjectsController#update; (issued from the example, body); status 302 -> /projects/1; actor User#1 role=member; db writes: none; flash {"notice":"Project updated"}

### F28

Example: "Reports shows the report"

```ruby
RSpec.describe "Reports" do
  let(:owner) { create_verified_user(name: "Owner") }
  let(:project) { Project.create!(name: "Apollo", owner: owner) }
  before { sign_in(owner) }
  # ...
  it "shows the report" do
    get "/projects/#{project.id}/report"
    expect(response).to be_successful
  end
```

Expectations that ran (all passed):
- be successful

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, before); status 302 -> /projects; db writes: none
- GET /projects/1/report -> ReportsController#show; (issued from the example, body); status 200; actor User#1 role=member; db writes: none; templates errors/generic.html.erb; rescue_from handled NoMethodError: undefined method `latest_invoice' for an instance of Project (raised at app/services/report_builder.rb:12, origin app); log ERROR: NoMethodError: undefined method `latest_invoice' for an instance of Project

### F29

Example: "Reports shows a friendly page when the report cannot be built"

```ruby
RSpec.describe "Reports" do
  let(:owner) { create_verified_user(name: "Owner") }
  let(:project) { Project.create!(name: "Apollo", owner: owner) }
  before { sign_in(owner) }
  # ...
  it "shows a friendly page when the report cannot be built" do
    allow(ReportBuilder).to receive(:new).and_raise(ReportBuilder::Unavailable)
    get "/projects/#{project.id}/report"
    expect(response.body).to include("Something went wrong")
  end
```

Expectations that ran (all passed):
- include "Something went wrong"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, before); status 302 -> /projects; db writes: none
- GET /projects/1/report -> ReportsController#show; (issued from the example, body); status 200; actor User#1 role=member; db writes: none; templates errors/generic.html.erb; rescue_from handled ReportBuilder::Unavailable: ReportBuilder::Unavailable (raised at app/controllers/reports_controller.rb:6, origin test_double); log ERROR: ReportBuilder::Unavailable: ReportBuilder::Unavailable

### F30

Example: "Unknown pages returns 404 for paths the app does not serve"

```ruby
RSpec.describe "Unknown pages" do
  # ...
  it "returns 404 for paths the app does not serve" do
    get "/wp-login.php"
    expect(response).to have_http_status(:not_found)
  end
```

Expectations that ran (all passed):
- respond with a not_found status code (404)

Runtime evidence:
- issued GET /wp-login.php answered 404 with Rails' exception page without reaching any controller (request 1)

### F31

Example: "Sessions signs in a known user"

```ruby
RSpec.describe "Sessions" do
  # ...
  it "signs in a known user" do
    user = create_verified_user(name: "Owner")
    post "/session", params: { email: user.email }
    expect(response).to redirect_to(projects_path)
  end
```

Expectations that ran (all passed):
- redirect to "/projects"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from the example, body); status 302 -> /projects; db writes: none

### F32

Example: "Sessions signs out"

```ruby
RSpec.describe "Sessions" do
  # ...
  it "signs out" do
    sign_in(create_verified_user(name: "Owner"))
    delete "/session"
    expect(response).to redirect_to(login_path)
  end
```

Expectations that ran (all passed):
- redirect to "/login"

Runtime evidence:
- POST /session -> SessionsController#create; (issued from a spec helper, body); status 302 -> /projects; db writes: none
- DELETE /session -> SessionsController#destroy; (issued from the example, body); status 302 -> /login; db writes: none

### F33

Example: "Sessions rejects unknown emails"

```ruby
RSpec.describe "Sessions" do
  # ...
  it "rejects unknown emails" do
    post "/session", params: { email: "nobody@verified.dev" }
    expect(response).to have_http_status(:unauthorized)
  end
```

Expectations that ran (all passed):
- respond with status code :unauthorized (401)

Runtime evidence:
- POST /session -> SessionsController#create; (issued from the example, body); status 401; db writes: none; templates sessions/new.html.erb

### F34

Example: "Status page shows the regional status banner"

```ruby
RSpec.describe "Status page" do
  # ...
  it "shows the regional status banner" do
    get "/status"
    expect(response.body).to include("All systems operational")
  end
```

Expectations that ran (all passed):
- include "All systems operational"

Runtime evidence:
- issued GET /status answered 400 with Rails' exception page (request 1)
- GET /status -> StatusController#show; (issued from the example, body); status 400; db writes: none; exception escaped the controller: ActionController::ParameterMissing: param is missing or the value is empty or invalid: region

### F35

Example: "Status page shows the banner for a region"

```ruby
RSpec.describe "Status page" do
  # ...
  it "shows the banner for a region" do
    get "/status", params: { region: "eu" }
    expect(response.body).to eq("eu: All systems operational")
  end
```

Expectations that ran (all passed):
- eq "eu: All systems operational"

Runtime evidence:
- GET /status?region=eu -> StatusController#show; (issued from the example, body); status 200; db writes: none; templates text template

### F36

Example: "Status page rejects a request without a region"

```ruby
RSpec.describe "Status page" do
  # ...
  it "rejects a request without a region" do
    get "/status"
    expect(response).to have_http_status(:bad_request)
  end
```

Expectations that ran (all passed):
- respond with status code :bad_request (400)

Runtime evidence:
- issued GET /status answered 400 with Rails' exception page (request 1)
- GET /status -> StatusController#show; (issued from the example, body); status 400; db writes: none; exception escaped the controller: ActionController::ParameterMissing: param is missing or the value is empty or invalid: region

### F37

Example: "ExportBuilder fails loudly when its thread is joined"

```ruby
RSpec.describe ExportBuilder do
  # ...
  it "fails loudly when its thread is joined" do
    thread = Thread.new { described_class.new(1).call }
    thread.report_on_exception = false
    expect { thread.join }.to raise_error(NameError, /ProjectCsvSerializer/)
  end
```

Expectations that ran (all passed):
- raise NameError with message matching /ProjectCsvSerializer/

Runtime evidence:
- a thread died with NameError: uninitialized constant ExportBuilder::ProjectCsvSerializer (re-raised by join)

