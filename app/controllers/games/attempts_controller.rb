module Games
  # 독서게임 결과 기록(P5.6 → Phase 3). 퀴즈 파이프라인 4종(quiz·classic·vocab·whoami) 공통
  # 제출 엔드포인트. 채점 → QuizAttempt 생성/finalize → award_points(레벨·진화·뱃지 연쇄) 후 복귀.
  class AttemptsController < BaseController
    def create
      quiz = Quiz.published.find(params[:quiz_id])
      authorize QuizAttempt.new(quiz: quiz, user: current_user), :create?

      # whoami 는 시작 시 attempt 를 선생성하므로 그 행을 finalize 한다(서버 힌트수 기준 채점, C1).
      prebuilt = prebuilt_attempt(quiz)

      # hint_reveal(whoami): 채점되는 attempt 는 반드시 힌트를 공개한 그 선생성 attempt 여야 한다(C1).
      # attempt_id 를 생략하면 hints_used=0 인 새 attempt 로 채점돼 힌트 페널티가 우회되므로(H1)
      # 거부하고 게임을 처음부터 다시 시작시킨다(QuizPlay 의 server_hints_used fail-safe 와 이중 방어).
      if quiz.content_axis == "hint_reveal" && prebuilt.nil?
        return redirect_to games_whoami_play_path(book_id: quiz.book_id),
                           alert: "게임을 처음부터 다시 시작해 주세요."
      end

      attempt = QuizPlay.new(quiz: quiz, user: current_user, attempt: prebuilt).record!(submitted_answers)
      # 게임 완료 원장 기록 + 신규 기록 시 몬스터 해금 재평가(Phase 3B). game_type 은 검증된 표면 선언.
      play = record_game_play!(game_type: params[:game], book_id: quiz.book_id)
      # 신규 GamePlay(중복 재제출 아님)일 때만 미션 진행 평가(menu_refactor 심화 §2.A.3, 몬스터 해금 앞).
      Missions::EvaluateProgress.new(current_user).on_game_play(play) if play
      discovered = play ? evaluate_monster_unlocks(current_user) : []
      redirect_to redirect_target(params[:game], quiz), notice: with_discovery(result_notice(attempt), discovered)
    end

    private

    # 선생성 attempt(whoami)만 본인·같은 퀴즈 소유를 검증해 재사용한다. 없거나 불일치면 새로 만든다.
    def prebuilt_attempt(quiz)
      return nil if params[:attempt_id].blank?

      current_user.quiz_attempts.find_by(id: params[:attempt_id], quiz_id: quiz.id)
    end

    # 실제 지급된 델타 기준의 정직한 안내(§1.2). 재플레이·재롤로 추가 포인트가 0이면
    # "얻었어요"라고 말하지 않는다 — 파밍 차단 취지와 UX 를 일치시킨다.
    def result_notice(attempt)
      if attempt.awarded_delta.to_i.positive?
        "#{attempt.score}문제 정답! #{attempt.awarded_delta}포인트를 얻었어요."
      else
        "#{attempt.score}문제 정답! 이미 받은 최고 기록이라 추가 포인트는 없어요."
      end
    end

    # answers[question_id] = 타입별 응답(mcq=보기 인덱스 / matching=좌→우 인덱스 해시 / hint_reveal=텍스트).
    # 채점기가 타입별로 coerce 하므로 여기서는 원형(unsafe_h)만 넘긴다 — 인덱스로 뭉개지 않는다.
    def submitted_answers
      raw = params[:answers]
      return {} unless raw.respond_to?(:each_pair)

      raw.to_unsafe_h.transform_keys(&:to_s)
    end

    # 온디맨드(system) 판은 그 표면의 play 로(새 판 시작), 교사 퀴즈(id)는 원래 show 로 복귀한다.
    def redirect_target(game, quiz)
      if quiz.origin == "system"
        on_demand_play_path(game.to_s, quiz.book_id)
      else
        teacher_show_path(game.to_s, quiz)
      end
    end

    def on_demand_play_path(game, book_id)
      case game
      when "classic" then games_classic_play_path(book_id: book_id)
      when "vocab" then games_vocab_play_path(book_id: book_id)
      when "whoami" then games_whoami_play_path(book_id: book_id)
      else games_quiz_play_path(book_id: book_id)
      end
    end

    # 교사 published mcq 퀴즈(id)는 quiz show 로 단일 재생한다.
    def teacher_show_path(_game, quiz)
      games_quiz_path(quiz)
    end
  end
end
