require "test_helper"

class ApplicationBrandingTest < ActionDispatch::IntegrationTest
  test "default page title and application name use the Korean service name" do
    get new_session_path

    assert_response :success
    assert_select "title", text: "책갈피"
    assert_select "meta[name='application-name'][content='책갈피']", count: 1
  end
end
