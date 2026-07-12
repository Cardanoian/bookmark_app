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

  test "search filters by region and gu and includes gu in the payload" do
    School.create!(name: "서울강남초", region: "서울특별시교육청", gu: "강남구")
    School.create!(name: "부산해운대초", region: "부산광역시교육청", gu: "해운대구")

    get schools_search_path, params: { region: "서울특별시교육청", gu: "강남구" }

    body = response.parsed_body
    assert_equal 1, body.size
    assert_equal "서울강남초", body.first["name"]
    assert_equal "강남구", body.first["gu"]
  end

  test "gus returns distinct 시군구 for a region excluding blanks" do
    School.create!(name: "A초", region: "서울특별시교육청", gu: "강남구")
    School.create!(name: "B초", region: "서울특별시교육청", gu: "강남구")
    School.create!(name: "C초", region: "서울특별시교육청", gu: "서초구")
    School.create!(name: "D초", region: "서울특별시교육청", gu: nil)
    School.create!(name: "E초", region: "부산광역시교육청", gu: "해운대구")

    get schools_gus_path, params: { region: "서울특별시교육청" }

    assert_response :success
    assert_equal %w[강남구 서초구], response.parsed_body, "중복 제거·정렬·빈 gu 제외"
  end

  test "gus returns an empty array when region is blank" do
    get schools_gus_path

    assert_response :success
    assert_equal [], response.parsed_body
  end

  test "classrooms returns only the given school's classrooms without authentication" do
    school = School.create!(name: "스코프초")
    other = School.create!(name: "다른초")
    Classroom.create!(school: school, grade: 3, class_no: 1)
    Classroom.create!(school: school, grade: 1, class_no: 2)
    Classroom.create!(school: other, grade: 5, class_no: 1)

    get school_classrooms_path(id: school.id)

    assert_response :success
    body = response.parsed_body
    assert_equal 2, body.size, "선택 학교 학급만(전국 전량 로드 아님)"
    assert_equal [ "1학년 2반", "3학년 1반" ], body.map { |classroom| classroom["label"] }
  end
end
