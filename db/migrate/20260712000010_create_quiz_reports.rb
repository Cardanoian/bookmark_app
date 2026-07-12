# 온디맨드 게임 콘텐츠 신고(무게이트 롤아웃 안전장치, TODO 후속 정밀화).
# 콘텐츠축 캐시 quiz 당 **1인 1신고**((quiz, user) unique, cheer/book_intro_vote 패턴) +
# quizzes.reports_count 카운터 캐시로 "서로 다른 신고자 수"를 센다. 서로 다른 신고자가
# Games::ContentProvider::REPORT_HIDE_THRESHOLD 에 도달하면 자동 숨김+재생성한다.
class CreateQuizReports < ActiveRecord::Migration[8.1]
  def change
    add_column :quizzes, :reports_count, :integer, default: 0, null: false

    create_table :quiz_reports do |t|
      t.references :quiz, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :quiz_reports, [ :quiz_id, :user_id ], unique: true
  end
end
