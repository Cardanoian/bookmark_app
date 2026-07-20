# 전국 공유 문제은행 UGC(게임 재구성 Phase 3, §3.5·§4). 학생이 그 책의 문제(객관식·나는 누구게?)를
# 출제하면 pending 상태로 담임 검토 큐에 쌓이고, 담임이 내용 수정·밴드 지정·승인하면
# system-scope·global·band-keyed 풀 퀴즈로 물질화되어 전국 공유 풀에 편입된다(ContributionPublisher).
# Quiz/풀 밖의 별도 pending 테이블 — 승인 전까지는 아무에게도 노출되지 않는다.
#   content_axis : mcq(독서 퀴즈) / hint_reveal(나는 누구게?). Quiz.content_axis 와 심볼명 공유.
#   band         : 작성자 학년 파생 기본, 교사 검수 때 조정(연령 적합성). Quiz.band 미러.
#   payload      : 문항 페이로드 JSON(mcq={prompt,choices[4],answer_index,explanation} /
#                  hint_reveal={answer,hints[],explanation}).
#   status       : pending(0) / approved(1) / rejected(2).
#   reviewed_by  : 승인·반려한 교사(nullable).
class CreateQuizContributions < ActiveRecord::Migration[8.1]
  def change
    create_table :quiz_contributions do |t|
      # user/book/classroom 은 pending 기여의 **임시 작성자 소유 행**이라 부모 삭제 시 함께 정리한다
      # (cascade). 승인돼 물질화된 풀 Quiz 는 system_user 소유의 **독립 행**이라 작성 학생·원본 도서가
      # 삭제돼도 무관하게 생존한다(감사기록만 사라짐, 보상 없음이라 무해) — User#quiz_contributions
      # dependent: :destroy 와 정합.
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :book, null: false, foreign_key: { on_delete: :cascade }
      t.references :classroom, null: false, foreign_key: { on_delete: :cascade }
      # 승인·반려 교사(nullable). 리뷰어 삭제는 기여 자체를 무효화하지 않으므로 참조만 끊는다(nullify).
      t.references :reviewed_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :content_axis, null: false, default: 0
      t.integer :band, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.json :payload
      t.timestamps
    end

    # 담임 검토 큐(학급 학생들의 pending) 조회용 복합 인덱스.
    add_index :quiz_contributions, [ :classroom_id, :status ]
  end
end
