# 게임 재구성 Phase 1 — 어휘 낚시(vocab) hard-delete + matching 퀴즈 콘텐츠 정리(계획서 §6).
#
# 정수 리터럴을 쓴다(모델 enum 비의존): game_type vocab=2, quiz content_axis matching=1.
# 삭제 순서 = 리프(game_plays) → matching 퀴즈 자식(question/attempt/report) → matching 퀴즈.
# 되돌릴 수 없는 손실 없음(계획서 §6): 몬스터·포인트·완료미션은 래칫이라 원장 삭제로 회수되지 않고,
# 미해금 진행 카운트만 감소한다(self-heal 재지급). dev 에는 vocab game_plays 0건.
class HardDeleteVocabGame < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM game_plays WHERE game_type = 2"                                                    # vocab=2
    execute "DELETE FROM quiz_questions WHERE quiz_id IN (SELECT id FROM quizzes WHERE content_axis = 1)"   # matching=1
    execute "DELETE FROM quiz_attempts  WHERE quiz_id IN (SELECT id FROM quizzes WHERE content_axis = 1)"
    execute "DELETE FROM quiz_reports   WHERE quiz_id IN (SELECT id FROM quizzes WHERE content_axis = 1)"
    execute "DELETE FROM quizzes WHERE content_axis = 1"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
