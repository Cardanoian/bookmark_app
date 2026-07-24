require "test_helper"

class AdminRecommendationImportsTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = User.create!(name: "추천관리자", role: :superadmin, password: "password")
    login_as @superadmin
  end

  test "superadmin uploads XLSX and sees active recommendation list" do
    file = build_recommendation_xlsx([
      { section: "어린이문학", title: "관리 추천책", author: "추천 작가", publisher: "추천사", isbn: "9787777777779" }
    ])

    assert_difference -> { RecommendationImport.count }, 1 do
      post admin_recommendation_imports_path,
           params: { file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: "2026추천.xlsx") }
    end

    assert_redirected_to admin_recommendation_imports_path
    follow_redirect!
    assert_response :success
    assert_match "추천도서 1권을 업데이트했어요", response.body
    assert_match "관리 추천책", response.body
    assert_equal @superadmin, RecommendationImport.current.imported_by
  ensure
    file&.close!
  end

  test "invalid XLSX reports an error without creating history" do
    file = Tempfile.new([ "invalid", ".xlsx" ])
    file.write("broken")
    file.flush

    assert_no_difference -> { RecommendationImport.count } do
      post admin_recommendation_imports_path,
           params: { file: Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") }
    end
    assert_redirected_to admin_recommendation_imports_path
    follow_redirect!
    assert_match "올바른 XLSX 파일이 아닙니다", response.body
  ensure
    file&.close!
  end
end
