# reports.book_id → books FK 의 on_delete 를 모델 의도(dependent: :nullify, Book#has_many :reports)와
# 정합화한다(#6). 기존 FK 는 on_delete 미지정(=RESTRICT)이라, 도서를 직접 SQL 로 삭제하면 참조
# 독후감이 있을 때 삭제가 막혀 모델의 nullify 계약과 어긋난다. reports.book_id 는 nullable 이므로
# on_delete: :nullify 로 바꿔 부모(book) 삭제 시 자식(report)을 남기고 참조만 끊는다.
#
# SQLite 는 FK 변경을 테이블 재빌드(12단계 복사)로 처리한다. up/down 모두 재빌드하며 데이터는
# 그대로 복사되므로 왕복 무손실이다(#8 down 왕복 테스트로 검증).
class AlignReportsBooksFkOnDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :reports, :books if foreign_key_exists?(:reports, :books)
    add_foreign_key :reports, :books, on_delete: :nullify
  end

  def down
    remove_foreign_key :reports, :books if foreign_key_exists?(:reports, :books)
    add_foreign_key :reports, :books
  end
end
