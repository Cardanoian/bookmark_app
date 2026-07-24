# whoami(hint_reveal) 서버 권위 힌트 카운터(Phase 3 §3.2b, C1). 힌트 공개수를 세션쿠키가
# 아니라 **attempt 행(서버측)**에 저장한다 — 구(舊) 쿠키 replay(count=0)로 위조 우회하는
# stale-cookie 공격면을 없앤다(EXECUTOR-NOTE #1). { "<question_id>" => 공개한 힌트 수 } JSON.
class AddHintRevealsToQuizAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :quiz_attempts, :hint_reveals, :json, default: {}, null: false
  end
end
