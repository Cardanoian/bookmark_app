require "test_helper"
require Rails.root.join("db/migrate/20260719190354_backfill_squished_book_titles.rb")

# 백필 마이그레이션(레거시 book_title 공백 정규화) 전용 테스트. 모델 콜백 normalize_book_title 은
# 신규 저장만 정규화하므로, 이미 영속된 비정규 데이터를 콜백 우회(update_columns)로 심어
# 마이그레이션 up 경로(find_each + update_columns)를 직접 실행해 검증한다(quiz_backfill_test 관례).
# 데이터 전용(DDL 없음)이라 트랜잭션 테스트 그대로 안전하다.
class BackfillSquishedBookTitlesTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "백필학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "백필학생", password: "password")
  end

  test "up 은 레거시 이중공백 book_title 을 squish 정규형으로 백필한다" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "정상 제목", body: "본문")
    # 콜백을 우회해 이미 저장된 비정규 값을 심는다(제약 도입 전 레거시 데이터 재현).
    report.update_columns(book_title: "이중  공백   제목")

    BackfillSquishedBookTitles.new.up

    assert_equal "이중 공백 제목", report.reload.book_title
  end

  test "up 은 이미 정규화된 값·book 연결 독후감을 건드리지 않고 재실행에 멱등이다" do
    normal = Report.create!(user: @student, classroom: @classroom, book_title: "정상 제목", body: "본문")
    linked_book = Book.create!(title: "긴긴밤", author: "루리")
    with_book = Report.create!(user: @student, classroom: @classroom, book: linked_book, body: "본문")

    BackfillSquishedBookTitles.new.up
    BackfillSquishedBookTitles.new.up # 재실행해도 결과가 같아야 한다(멱등)

    assert_equal "정상 제목", normal.reload.book_title
    assert_nil with_book.reload.book_title, "book 연결 독후감은 book_title 이 없어 그대로 nil"
  end

  test "down 은 성공 no-op 이다(비가역 데이터 정규화)" do
    assert_nothing_raised { BackfillSquishedBookTitles.new.down }
  end
end
