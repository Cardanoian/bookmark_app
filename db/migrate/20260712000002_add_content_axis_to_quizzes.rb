# 콘텐츠축 캐시 키 + 멱등 델타 origin 분기 토대(Phase 1 §1.1).
#   content_axis  : 캐시·dedup 키(4값: mcq/matching/hint_reveal/balance_vote). teacher 퀴즈는 nil 허용.
#   band          : 학년군(g12/g34/g56). 콘텐츠축 상한 비교의 스케일 경계.
#   origin        : teacher(현행 per-quiz 멱등) / system(콘텐츠축 캐시). 기본 teacher.
#   generation_status : 내부 캐시 상태(ready/warming/failed). 기본 ready.
#   content_version   : 재생성 버전. 기본 1.
#   reported          : 신고 숨김 플래그. 기본 false.
# 표면(surface)은 요청시점 결정이라 컬럼으로 저장하지 않는다(C6: on_demand enum 없음).
# 콘텐츠축 델타 상한 조회용 지원 인덱스도 함께 만든다(부분 유니크 인덱스는 Phase 2b).
class AddContentAxisToQuizzes < ActiveRecord::Migration[8.1]
  def change
    add_column :quizzes, :content_axis, :integer
    add_column :quizzes, :band, :integer
    add_column :quizzes, :origin, :integer, default: 0, null: false
    add_column :quizzes, :generation_status, :integer, default: 0, null: false
    add_column :quizzes, :content_version, :integer, default: 1, null: false
    add_column :quizzes, :reported, :boolean, default: false, null: false

    add_index :quizzes, [ :book_id, :band, :content_axis, :origin ],
              name: "index_quizzes_on_content_axis_delta"
  end
end
