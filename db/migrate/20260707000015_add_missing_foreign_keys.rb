# 누락된 선택적 FK 제약 추가(§2.5). 참조 컬럼은 모두 nullable 이므로 부모 삭제 시
# 자식 행을 남기고 참조만 끊는 on_delete: :nullify 로 통일한다 — 고아행 생성은
# 막되(무결성), 부모(school/book/classroom) 삭제를 제약이 차단하지 않도록 한다.
# 컬럼 존재/기존 FK/고아행을 각각 방어적으로 확인해 재실행·기존 데이터에도 안전하다.
class AddMissingForeignKeys < ActiveRecord::Migration[8.1]
  FOREIGN_KEYS = [
    { from: :challenges,     to: :schools,    column: :school_id },
    { from: :challenges,     to: :books,      column: :book_id },
    { from: :topics,         to: :classrooms, column: :classroom_id },
    { from: :topics,         to: :schools,    column: :school_id },
    { from: :topics,         to: :books,      column: :book_id },
    { from: :library_events, to: :schools,    column: :school_id },
    { from: :library_events, to: :books,      column: :book_id },
    { from: :seasons,        to: :schools,    column: :school_id },
    { from: :quizzes,        to: :books,      column: :book_id },
    { from: :quizzes,        to: :classrooms, column: :classroom_id },
    { from: :missions,       to: :books,      column: :book_id },
    { from: :library_loans,  to: :schools,    column: :school_id }
  ].freeze

  def up
    FOREIGN_KEYS.each do |fk|
      next unless column_exists?(fk[:from], fk[:column])
      next if foreign_key_exists?(fk[:from], fk[:to], column: fk[:column])

      nullify_orphans(fk)
      add_foreign_key fk[:from], fk[:to], column: fk[:column], on_delete: :nullify
    end
  end

  def down
    FOREIGN_KEYS.reverse_each do |fk|
      next unless foreign_key_exists?(fk[:from], fk[:to], column: fk[:column])

      remove_foreign_key fk[:from], fk[:to], column: fk[:column]
    end
  end

  private

  # 부모가 없는 기존 참조를 NULL 로 정리해 제약 추가 실패(고아행)를 예방한다.
  def nullify_orphans(fk)
    execute(<<~SQL.squish)
      UPDATE #{fk[:from]}
      SET #{fk[:column]} = NULL
      WHERE #{fk[:column]} IS NOT NULL
        AND #{fk[:column]} NOT IN (SELECT id FROM #{fk[:to]})
    SQL
  end
end
