module Games
  # 독서게임 10종 공통 베이스(P5.6). 게임 카탈로그(한국어 라벨) + published 퀴즈 로딩.
  class BaseController < ApplicationController
    # 게임 키 → 표시 이름(도감/플레이스홀더 라벨). 실동작 3종 + 증분 7종.
    CATALOG = {
      "quiz" => { name: "독서 퀴즈", icon: "❓", playable: true },
      "golden" => { name: "골든벨 서바이벌", icon: "🔔", playable: true },
      "bingo" => { name: "독서 빙고", icon: "🎉", playable: true },
      "book" => { name: "책 소개 대결", icon: "📖", playable: false },
      "classic" => { name: "고전 읽기 여행", icon: "🏛️", playable: false },
      "battle" => { name: "독서 배틀", icon: "⚔️", playable: false },
      "balance" => { name: "밸런스 게임", icon: "⚖️", playable: false },
      "vocab" => { name: "어휘 낚시", icon: "🎣", playable: false },
      "whoami" => { name: "나는 누구게?", icon: "🕵️", playable: false },
      "marathon" => { name: "독서 마라톤", icon: "🏃", playable: false }
    }.freeze

    private

    # published 퀴즈를 찾아 인가(QuizPolicy#show?)한 뒤 반환. 미게시/없음 → 404.
    def load_playable_quiz
      quiz = Quiz.published.find(params[:id])
      authorize quiz, :show?
      quiz
    end

    def catalog_entry
      CATALOG.fetch(controller_name, { name: controller_name, icon: "🎮", playable: false })
    end
    helper_method :catalog_entry
  end
end
