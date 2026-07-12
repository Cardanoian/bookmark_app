module Games
  # 나는 누구게?(Phase 3 온디맨드, §3.2b hint_reveal 서버 권위). whoami 표면 → hint_reveal 콘텐츠축.
  #
  # 수명주기(EXECUTOR-NOTE #2): reveal_hint 가 :attempt 를 요구하므로 **게임 시작 시 attempt 를
  # 선생성**한다. play(book_id) → 리졸브 + attempt 선생성 → show(attempt id)로 리다이렉트.
  # 힌트 공개 카운터는 세션쿠키가 아니라 **attempt 행(hint_reveals JSON, DB)**에 저장한다 —
  # 구 쿠키 replay(count=0) 위조 우회를 원천 차단(EXECUTOR-NOTE #1, C1). 채점은 그 서버 카운트로만.
  class WhoamiController < BaseController
    # play=온디맨드 진입(book_id)으로 attempt 선생성 후 안정적인 show(attempt id)로 이동.
    # 제출 후 새 판으로 올 때 결과 안내(flash)가 show 까지 살아남도록 keep 한다(play→show 이중 리다이렉트).
    #
    # 미확정 attempt 재사용(Phase 3 리뷰 LOW 후속): 같은 퀴즈에 **아직 제출하지 않은(played_at IS NULL)**
    # 선생성 attempt 가 있으면 재사용한다. 이렇게 하면 ① play 재진입마다 0점 빈 attempt 가 누적되지 않고,
    # ② 힌트를 공개한 뒤 play 로 재진입해 **힌트 카운터 0인 새 attempt** 로 페널티를 우회(H2)하는 구멍도
    # 닫힌다(재진입해도 이미 공개한 힌트가 그대로 남는 같은 attempt 로 돌아옴). 확정된(제출된) attempt 는
    # 재사용하지 않으므로 새 판을 시작하려면 정상적으로 새 attempt 가 생성된다.
    def play
      quiz = resolve_on_demand("whoami")
      authorize QuizAttempt.new(quiz: quiz, user: current_user), :create?
      attempt = current_user.quiz_attempts.where(quiz: quiz, played_at: nil).order(:id).last ||
                quiz.quiz_attempts.create!(user: current_user, hint_reveals: {}, score: 0, points_awarded: 0)
      flash.keep(:notice)
      redirect_to games_whoami_path(attempt)
    end

    # show=attempt 상태(선생성 행)로 렌더. 이미 공개한 힌트만 서버 상태에서 보여 준다(정답·잔여수 무유출).
    def show
      @attempt = current_user.quiz_attempts.find(params[:id])
      @quiz = @attempt.quiz
      authorize @quiz, :show?
    end

    # reveal_hint=공개 요청마다 **서버 카운터 1 증가**(attempt.hint_reveals). 응답은 다음 힌트만
    # (다시 show 로 렌더). 잔여 힌트수·정답은 노출하지 않는다. 클라이언트 주장 힌트수는 무시된다.
    def reveal_hint
      attempt = current_user.quiz_attempts.find(params[:attempt])
      authorize attempt, :update?
      question = attempt.quiz.quiz_questions.find(params[:question_id])

      reveals = (attempt.hint_reveals || {}).dup
      key = question.id.to_s
      revealed = reveals[key].to_i
      if revealed < question.hints_list.length
        reveals[key] = revealed + 1
        attempt.update!(hint_reveals: reveals)
      end

      redirect_to games_whoami_path(attempt)
    end
  end
end
