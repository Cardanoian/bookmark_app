# 독서게임 3종 표시 헬퍼 — 게임 종류를 디자인 토큰 액센트 색으로 구분한다.
module GamesHelper
  # key → 목록/진입 칩 배경·글자색 클래스(디자인 토큰). 미지정 key 는 quiz 액센트로 폴백.
  # 게임 재구성 Phase 1: 살아있는 표면(quiz·whoami·book)만 둔다(classic/vocab 제거).
  GAME_ACCENTS = {
    "quiz"    => "bg-surface-featured text-brand-blue",
    "whoami"  => "bg-rose-light text-coral-dark",
    "book"    => "bg-brand-orange-light text-coral-dark"
  }.freeze

  def game_accent(key)
    GAME_ACCENTS.fetch(key.to_s, GAME_ACCENTS["quiz"])
  end
end
