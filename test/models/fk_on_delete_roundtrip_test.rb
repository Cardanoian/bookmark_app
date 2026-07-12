require "test_helper"
require Rails.root.join("db/migrate/20260712000005_align_reports_books_fk_on_delete.rb")
require Rails.root.join("db/migrate/20260712000006_add_on_delete_to_monster_species_self_fk.rb")

# FK on_delete 정렬(#6 reports→books, #8 monster_species 자기참조)의 동작 + SQLite 테이블
# 재빌드 up/down 왕복 무손실을 검증한다.
#
# DDL(테이블 재빌드)은 트랜잭션 밖에서 커밋되므로 이 클래스는 트랜잭션 테스트를 끈다.
# 각 테스트는 고유 데이터를 만들고 teardown 에서 정리 + 스키마를 up(schema.rb) 상태로 복원한다.
class FkOnDeleteRoundtripTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  REPORTS_FK = AlignReportsBooksFkOnDelete.new
  SPECIES_FK = AddOnDeleteToMonsterSpeciesSelfFk.new

  def conn
    ActiveRecord::Base.connection
  end

  teardown do
    # 항상 up 상태(on_delete: :nullify)로 복원해 다른 테스트를 오염시키지 않는다.
    silently { REPORTS_FK.up } unless nullify?(:reports, :books)
    unless nullify?(:monster_species, :monster_species, column: :evolves_from_id)
      silently { SPECIES_FK.up }
    end
    # 생성한 행 정리(트랜잭션 롤백이 없으므로 수동).
    MonsterSpecies.where("key LIKE 'fkrt_%'").delete_all
    Report.where(book_title: "FKRT책").delete_all
    Book.where(title: "FKRT도서").delete_all
    User.where(name: "FKRT유저").delete_all
    Classroom.joins(:school).where(schools: { name: "FKRT학교" }).delete_all
    School.where(name: "FKRT학교").delete_all
  end

  # reports.book_id → books 는 부모 삭제 시 자식을 남기고 참조만 끊는다(DB FK on_delete: nullify).
  test "deleting a book nullifies referencing reports at the DB level (#6)" do
    book = Book.create!(title: "FKRT도서", category: :recommended)
    report = create_report(book)

    Book.where(id: book.id).delete_all # AR 콜백 우회 → 순수 DB FK 동작 검증

    assert_nil report.reload.book_id, "book 삭제 시 report.book_id 는 DB FK 로 NULL 이 된다"
  end

  # monster_species 자기참조: 진화 이전 폼 삭제 시 다음 폼의 evolves_from_id 를 끊는다.
  test "deleting a parent species nullifies the child's evolves_from_id (#8)" do
    parent = MonsterSpecies.create!(key: "fkrt_parent", stage: 1, dex_no: 9001)
    child = MonsterSpecies.create!(key: "fkrt_child", stage: 2, dex_no: 9001, evolves_from: parent)

    MonsterSpecies.where(id: parent.id).delete_all

    assert_nil child.reload.evolves_from_id, "부모 종 삭제 시 자식 evolves_from_id 는 NULL 이 된다"
  end

  # reports→books: up→down→up 왕복에도 데이터가 보존되고 on_delete 만 뒤바뀐다.
  test "reports->books migration up/down is a lossless round-trip (#6)" do
    book = Book.create!(title: "FKRT도서", category: :recommended)
    report = create_report(book)

    silently { REPORTS_FK.down } # RESTRICT 로 되돌림
    assert_not nullify?(:reports, :books), "down 은 on_delete 를 제거한다"
    assert_equal book.id, report.reload.book_id, "테이블 재빌드에도 참조 데이터 보존"

    silently { REPORTS_FK.up } # nullify 재적용
    assert nullify?(:reports, :books), "up 은 on_delete: nullify 를 복원한다"
    assert_equal book.id, report.reload.book_id, "왕복 후에도 데이터 무손실"
  end

  # monster_species 자기참조: up→down→up 왕복 무손실.
  test "monster_species self-fk migration up/down is a lossless round-trip (#8)" do
    parent = MonsterSpecies.create!(key: "fkrt_parent", stage: 1, dex_no: 9001)
    child = MonsterSpecies.create!(key: "fkrt_child", stage: 2, dex_no: 9001, evolves_from: parent)

    silently { SPECIES_FK.down }
    assert_not nullify?(:monster_species, :monster_species, column: :evolves_from_id), "down 은 on_delete 제거"
    assert_equal parent.id, child.reload.evolves_from_id, "재빌드에도 자기참조 보존"

    silently { SPECIES_FK.up }
    assert nullify?(:monster_species, :monster_species, column: :evolves_from_id), "up 은 nullify 복원"
    assert_equal parent.id, child.reload.evolves_from_id, "왕복 후에도 무손실"
  end

  private

  def create_report(book)
    school = School.create!(name: "FKRT학교")
    classroom = Classroom.create!(school: school, grade: 5, class_no: 1)
    user = User.create!(school: school, classroom: classroom, name: "FKRT유저", password: "password")
    Report.create!(user: user, classroom: classroom, book: book, book_title: "FKRT책", body: "본문")
  end

  # 주어진 FK 의 on_delete 가 :nullify 인지.
  def nullify?(from, to, column: nil)
    fk = conn.foreign_keys(from.to_s).find do |f|
      f.to_table == to.to_s && (column.nil? || f.options[:column].to_s == column.to_s)
    end
    fk&.on_delete == :nullify
  end

  def silently(&block)
    ActiveRecord::Migration.suppress_messages(&block)
  end
end
