require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Personal")
    company = @workspace.companies.create!(name: "Acme Analytics", domain: "acme.com")
    @lead = Lead.create!(workspace: @workspace, company: company)
  end

  test "does not challenge for credentials outside production" do
    get leads_url
    assert_response :success
    assert_nil response.headers["WWW-Authenticate"]

    get review_index_url
    assert_response :success
    assert_nil response.headers["WWW-Authenticate"]

    get lead_url(@lead)
    assert_response :success
    assert_nil response.headers["WWW-Authenticate"]
  end

  # The guard is installed at class-definition time under Rails.env.production?,
  # so it cannot be exercised from the test environment without booting a second
  # environment. Pin its shape instead: gated on production, and reading both
  # credentials with ENV.fetch so a deploy missing either secret fails to boot
  # rather than coming up open.
  test "the basic auth guard is gated on production and fetches both secrets strictly" do
    source = Rails.root.join("app/controllers/application_controller.rb").read

    assert_match(/if Rails\.env\.production\?\s+http_basic_authenticate_with\(/, source)
    assert_match(/name: ENV\.fetch\("LEADS_PIPELINE_USER"\)/, source)
    assert_match(/password: ENV\.fetch\("LEADS_PIPELINE_PASSWORD"\)/, source)
    assert_no_match(/ENV\.fetch\("LEADS_PIPELINE_(USER|PASSWORD)",/, source)
  end
end
