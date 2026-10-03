# frozen_string_literal: true

RSpec.describe "Unknown pages" do
  it "returns 404 for paths the app does not serve" do
    get "/wp-login.php"
    expect(response).to have_http_status(:not_found)
  end
end
