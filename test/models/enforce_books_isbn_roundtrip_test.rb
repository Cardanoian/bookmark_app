require "test_helper"
require Rails.root.join("db/migrate/20260718000011_enforce_books_isbn.rb")

# SQLite books 테이블 재빌드가 자식 FK의 CASCADE/SET NULL을 발동하지 않는지 검증한다.
class EnforceBooksIsbnRoundtripTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  MIGRATION = EnforceBooksIsbn.new

  test "ISBN 제약 down/up 왕복에도 추천목록과 퀴즈의 book 참조가 보존된다" do
    book = Book.create!(title: "ISBNRT도서", isbn: TestBookIsbn.next)
    creator = User.create!(name: "ISBNRT시스템", role: :superadmin, password: "password")
    quiz = Quiz.create!(title: "ISBNRT퀴즈", created_by: creator, book: book, scope: :global)
    recommendation_import = RecommendationImport.create!(
      filename: "isbn-roundtrip.xlsx", file_digest: SecureRandom.hex(32),
      imported_at: Time.current, item_count: 1
    )
    recommendation = recommendation_import.book_recommendations.create!(
      book: book, section: "어린이문학", position: 1
    )

    silently { MIGRATION.down }
    assert_equal book.id, quiz.reload.book_id
    assert_equal book.id, recommendation.reload.book_id

    silently { MIGRATION.up }
    assert_equal book.id, quiz.reload.book_id
    assert_equal book.id, recommendation.reload.book_id
  end

  teardown do
    silently { MIGRATION.up } if Book.columns_hash.fetch("isbn").null
    RecommendationImport.where(filename: "isbn-roundtrip.xlsx").destroy_all
    Quiz.where(title: "ISBNRT퀴즈").destroy_all
    Book.where(title: "ISBNRT도서").delete_all
    User.where(name: "ISBNRT시스템").delete_all
  end

  private

  def silently(&block)
    ActiveRecord::Migration.suppress_messages(&block)
  end
end
