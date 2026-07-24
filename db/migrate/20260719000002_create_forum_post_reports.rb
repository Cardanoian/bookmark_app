# 독서 토론 신고 원장(reading_discussion PR). 토론 글당 1인 1신고(quiz_reports 패턴 복제).
# (forum_post_id, user_id) 유니크가 중복 신고를 막고, forum_posts.reports_count 를 counter_cache 로 센다.
# reason 은 선택(초등 눈높이 자유·nullable) — 자동숨김 없이 교사 대시보드 사후 검토 신호로만 쓴다.
class CreateForumPostReports < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_post_reports do |t|
      t.references :forum_post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :reason
      t.timestamps
    end

    add_index :forum_post_reports, [ :forum_post_id, :user_id ], unique: true
  end
end
