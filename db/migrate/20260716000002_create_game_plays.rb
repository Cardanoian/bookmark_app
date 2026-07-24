# 게임 완료 활동 원장(monster_unlocks.md §게임 판정, Phase 3B). 서버 권위 기록으로
# game_plays/distinct_games/game_books 해금 지표를 집계한다.
#
# 반복 새로고침·재제출 파밍을 막기 위해 같은 학생이 같은 날 같은 게임을 (같은 책으로)
# 여러 번 완료해도 1회만 인정한다. book_id 는 nullable(책 미연결 교사 퀴즈도 game_plays·
# distinct_games 에는 포함, game_books 에는 미포함)이고 SQLite 유니크 인덱스는 NULL 을 서로
# 구별하므로, 단일 (user,game_type,book_id,played_on) 유니크로는 book-less 재제출이 dedup 되지
# 않는다. 그래서 부분 유니크 인덱스 2개로 book 있는/없는 경우를 각각 dedup 한다
# (선례: index_quizzes_on_content_axis_dedup 부분 유니크).
class CreateGamePlays < ActiveRecord::Migration[8.1]
  def change
    create_table :game_plays do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :game_type, null: false
      t.references :book, null: true, foreign_key: true
      t.date :played_on, null: false

      t.timestamps
    end

    # book 있는 플레이: (user, game_type, book, 일자) 당 1회.
    add_index :game_plays, [ :user_id, :game_type, :book_id, :played_on ],
              unique: true, where: "book_id IS NOT NULL",
              name: "index_game_plays_daily_dedup_with_book"
    # book 없는 플레이: (user, game_type, 일자) 당 1회(book_id 를 키에서 뺀다 → NULL 구별 우회).
    add_index :game_plays, [ :user_id, :game_type, :played_on ],
              unique: true, where: "book_id IS NULL",
              name: "index_game_plays_daily_dedup_without_book"
  end
end
