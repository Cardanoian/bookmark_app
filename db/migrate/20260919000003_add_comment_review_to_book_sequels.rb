# 뒷이야기 AI 코멘트의 교사 승인(2026-09-19). 독후감 첨삭처럼 책갈피 도우미가 단 코멘트를 담임이 읽고
# (필요하면 고쳐) 승인해야 작성 학생에게 보인다.
#   reviewed_at    — 승인 시각. NULL 이면 미승인(학생에게 코멘트 비공개).
#   reviewed_by_id — 승인한 교사. 교사 계정이 지워져도 승인 사실은 남도록 nullify.
#   teacher_comment — 교사가 고친 코멘트. NULL 이면 ai_comment 를 그대로 승인한 것(AI 원문은 ai_comment 에 보존).
#
# 백필: 이 마이그레이션 전에 코멘트가 달린 글은 규칙상 이미 학생에게 보였다. 승인 대기로 되돌리면 학생
# 화면에서 코멘트가 사라지고 담임 검토 목록이 지난 글로 가득 차므로, 코멘트가 있는 기존 글은 승인된
# 것으로 둔다(reviewed_by 는 비워 "승인 제도 전 글"임을 남긴다 — 학생 화면은 이런 글에 "선생님이 확인한
# 코멘트"라고 쓰지 않는다). 새 글부터 승인을 거친다. 코멘트가 없는 옛 실패 글(failed)은 승인 대기로 들어가
# 담임이 직접 코멘트를 적어 줄 수 있다.
class AddCommentReviewToBookSequels < ActiveRecord::Migration[8.1]
  def up
    add_column :book_sequels, :reviewed_at, :datetime
    add_column :book_sequels, :teacher_comment, :text
    add_reference :book_sequels, :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }

    execute <<~SQL.squish
      UPDATE book_sequels SET reviewed_at = updated_at
      WHERE TRIM(COALESCE(ai_comment, '')) != ''
    SQL
  end

  def down
    remove_reference :book_sequels, :reviewed_by, foreign_key: { to_table: :users }
    remove_column :book_sequels, :teacher_comment
    remove_column :book_sequels, :reviewed_at
  end
end
