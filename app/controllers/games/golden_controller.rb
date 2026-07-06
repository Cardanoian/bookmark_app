module Games
  # 골든벨 서바이벌(실동작, P5.6). 같은 published 퀴즈를 서바이벌 UI 로 제시한다.
  class GoldenController < BaseController
    def show
      @quiz = load_playable_quiz
    end
  end
end
