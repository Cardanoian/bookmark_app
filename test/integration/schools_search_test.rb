require "test_helper"

class SchoolsSearchTest < ActionDispatch::IntegrationTest
  test "search returns matching schools as JSON without authentication" do
    School.create!(name: "서울강남초등학교", region: "서울특별시교육청")
    School.create!(name: "부산해운대초등학교", region: "부산광역시교육청")

    get schools_search_path, params: { q: "강남" }

    assert_response :success
    body = response.parsed_body
    assert_kind_of Array, body
    assert_equal 1, body.size
    assert_equal "서울강남초등학교", body.first["name"]
    assert body.first.key?("id")
    assert body.first.key?("region")
  end

  test "search returns an empty array when nothing matches" do
    get schools_search_path, params: { q: "존재하지않는학교" }

    assert_response :success
    assert_equal [], response.parsed_body
  end
end
