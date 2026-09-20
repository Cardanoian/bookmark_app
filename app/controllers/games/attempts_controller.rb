module Games
  # 독서게임 결과 기록(P5.6 → Phase 3 → 게임 재구성 Phase 1). 퀴즈 파이프라인 표면(quiz·whoami) 공통
  # 제출 엔드포인트. 채점·QuizAttempt 확정·포인트 적립·완료 원장은 QuizPlay 가 한 트랜잭션으로 남기고,
  # 여기서는 그 결과로 안내·이동·후속 평가(미션·챌린지·몬스터 해금)만 한다.
  class AttemptsController < BaseController
    def create
      quiz = Quiz.published.find(params[:quiz_id])
      authorize QuizAttempt.new(quiz: quiz, user: current_user), :create?

      # 게임 종류는 요청값(params[:game])이 아니라 검증한 퀴즈 유형에서 정한다(BUG_FIX_PLAN F4).
      # 예전 폼이 game 을 보내도 읽지 않는다 — 완료 원장과 이동 경로 모두 이 값만 따른다.
      # 받을 수 없는 퀴즈(matching·알 수 없는 축·축과 문항이 어긋남)는 저장·채점·보상 전에 돌려보낸다.
      game_type = quiz.play_game_type
      return redirect_to games_catalog_path, alert: "이 퀴즈는 지금 풀 수 없어요." unless game_type

      # whoami 는 시작 시 attempt 를 선생성하므로 그 행을 finalize 한다(서버 힌트수 기준 채점, C1).
      # · hint_reveal(whoami): 채점되는 attempt 는 반드시 힌트를 공개한 그 선생성 attempt 여야 한다 —
      #   attempt_id 를 생략하면 hints_used=0 인 새 attempt 로 채점돼 힌트 페널티가 우회된다(H1).
      # · attempt_id 를 보냈는데 본인·같은 퀴즈의 기록이 아니면 새 attempt 로 바꿔 받지 않는다 — 남의 기록·
      #   다른 퀴즈의 기록 번호로 "새 판"을 얻는 길을 두지 않는다.
      # 둘 다 거부하고 게임을 처음부터 다시 시작시킨다(QuizPlay 의 server_hints_used fail-safe 와 이중 방어).
      prebuilt = prebuilt_attempt(quiz)
      if prebuilt.nil? && (game_type == "whoami" || params[:attempt_id].present?)
        return redirect_to restart_path(game_type, quiz), alert: "게임을 처음부터 다시 시작해 주세요."
      end

      result = QuizPlay.new(quiz: quiz, user: current_user, attempt: prebuilt).record!(submitted_answers)

      # 실제 새 완료 원장이 생겼을 때만 미션·챌린지 진행과 몬스터 해금을 다시 평가한다(menu_refactor 심화
      # §2.A.3 — 미션·챌린지가 몬스터 해금 앞). 같은 날 같은 게임의 재플레이·같은 attempt 의 재전송은 nil 이다.
      # "추가 포인트 0"으로 판단하지 않는다 — 최고점을 못 넘은 정상 새 판도 활동 완료다.
      play = result.game_play
      Missions::EvaluateProgress.new(current_user).on_game_play(play) if play
      Challenges::EvaluateProgress.new(current_user).on_game_play(play) if play
      discovered = play ? evaluate_monster_unlocks(current_user) : []
      # 포인트를 실제로 얻었을 때만 보상 효과음(layouts/application 이 학생에게 렌더).
      flash[:sfx] = "reward" if result.awarded_delta.positive?
      redirect_to redirect_target(game_type, quiz), notice: with_discovery(result_notice(result), discovered)
    end

    private

    # 선생성 attempt(whoami)를 본인·같은 퀴즈 소유로 좁혀 찾는다. attempt_id 가 없으면 nil,
    # 있는데 못 찾아도 nil — 뒤의 경우는 create 가 거부한다(새 attempt 로 대체하지 않는다).
    def prebuilt_attempt(quiz)
      return nil if params[:attempt_id].blank?

      current_user.quiz_attempts.find_by(id: params[:attempt_id], quiz_id: quiz.id)
    end

    # 실제 지급된 델타 기준의 정직한 안내(§1.2). 재플레이·재롤로 추가 포인트가 0이면
    # "얻었어요"라고 말하지 않는다 — 파밍 차단 취지와 UX 를 일치시킨다. 같은 attempt 를 다시 보낸
    # 요청(새로 고침·두 번 누름)은 새 판이 아니므로 저장된 결과를 알려 준다(F1).
    def result_notice(result)
      if !result.newly_finalized?
        "이미 제출한 결과예요. 추가 포인트는 없어요."
      elsif result.awarded_delta.positive?
        "#{result.score}문제 정답! #{result.awarded_delta}포인트를 얻었어요. 경험치도 #{result.awarded_delta}XP 올랐어요."
      else
        "#{result.score}문제 정답! 이미 받은 최고 기록이라 추가 포인트는 없어요."
      end
    end

    # answers[question_id] = 타입별 응답(mcq=보기 인덱스 / hint_reveal=텍스트).
    # 채점기가 타입별로 coerce 하므로 여기서는 원형(unsafe_h)만 넘긴다 — 인덱스로 뭉개지 않는다.
    def submitted_answers
      raw = params[:answers]
      return {} unless raw.respond_to?(:each_pair)

      raw.to_unsafe_h.transform_keys(&:to_s)
    end

    # 온디맨드(system) 판은 그 표면의 play 로(새 판 시작), 교사 퀴즈(id)는 원래 show 로 복귀한다.
    def redirect_target(game_type, quiz)
      if quiz.origin == "system"
        on_demand_play_path(game_type, quiz.book_id)
      else
        games_quiz_path(quiz)
      end
    end

    # 거부한 제출이 돌아갈 곳 — 그 게임을 처음부터 다시 시작하는 화면. 책 없는 system 판은 없지만
    # (온디맨드는 책에서 시작한다) 방어적으로 카탈로그로 보낸다.
    def restart_path(game_type, quiz)
      return games_quiz_path(quiz) unless quiz.origin == "system"
      return games_catalog_path unless quiz.book_id

      on_demand_play_path(game_type, quiz.book_id)
    end

    def on_demand_play_path(game_type, book_id)
      case game_type
      when "whoami" then games_whoami_play_path(book_id: book_id)
      else games_quiz_play_path(book_id: book_id)
      end
    end
  end
end
