require "test_helper"

# P7.2/P7.3 전역 콘텐츠 CRUD 라운드트립: 학교·도서·뱃지·상점 아이템.
class AdminContentTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = User.create!(name: "총괄", role: :superadmin, password: "password")
    login_as @superadmin
  end

  test "school create and destroy" do
    assert_difference -> { School.count }, 1 do
      post admin_schools_path, params: { school: { name: "새로운초", region: "서울" } }
    end
    school = School.find_by(name: "새로운초")
    delete admin_school_path(school)
    assert_nil School.find_by(id: school.id)
  end

  test "book create and update" do
    assert_difference -> { Book.count }, 1 do
      post admin_books_path, params: { book: { title: "관리도서", author: "저자", category: "classic" } }
    end
    book = Book.find_by(title: "관리도서")
    patch admin_book_path(book), params: { book: { title: "수정도서" } }
    assert_equal "수정도서", book.reload.title
  end

  test "badge create" do
    assert_difference -> { Badge.count }, 1 do
      post admin_badges_path, params: { badge: { key: "admin_badge", name: "관리뱃지" } }
    end
  end

  test "shop_item create with JSON effect" do
    assert_difference -> { ShopItem.count }, 1 do
      post admin_shop_items_path, params: { shop_item: { name: "관리간식", category: "food", cost: 5, effect_json: '{"hunger": 3}' } }
    end
    assert_equal({ "hunger" => 3 }, ShopItem.find_by(name: "관리간식").effect)
  end

  test "shop_item create rejects invalid JSON effect" do
    assert_no_difference -> { ShopItem.count } do
      post admin_shop_items_path, params: { shop_item: { name: "깨진효과", category: "food", cost: 5, effect_json: "{broken" } }
    end
    assert_response :unprocessable_entity
  end

  test "quiz create with a nested question" do
    assert_difference -> { Quiz.count }, 1 do
      post admin_quizzes_path, params: { quiz: {
        title: "관리퀴즈", scope: "global", published: "1",
        quiz_questions_attributes: {
          "0" => { prompt: "질문?", choices: "가\n나\n다\n라", answer_number: 1, position: 1 }
        }
      } }
    end
    quiz = Quiz.find_by(title: "관리퀴즈")
    assert_equal @superadmin.id, quiz.created_by_id
    assert_equal %w[가 나 다 라], quiz.quiz_questions.first.choices
  end

  private
end
