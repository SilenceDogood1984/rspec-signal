# frozen_string_literal: true

RSpec.describe "Status page" do
  it "shows the regional status banner" do
    get "/status"
    expect(response.body).to include("All systems operational")
  end

  it "shows the banner for a region" do
    get "/status", params: { region: "eu" }
    expect(response.body).to eq("eu: All systems operational")
  end

  it "rejects a request without a region" do
    get "/status"
    expect(response).to have_http_status(:bad_request)
  end
end
