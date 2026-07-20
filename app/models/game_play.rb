# 게임 완료 활동 원장 1행(monster_unlocks.md §게임 판정, Phase 3B). 몬스터 해금 지표
# game_plays/distinct_games/game_books 의 서버 권위 소스.
#
# game_type 신뢰 경계: 퀴즈 표면은 서버가 Quiz 행만으론 표면을 권위적으로 구분할 수 없다
# (monster_unlocks.md §69). 그래서 퀴즈 표면은 **검증된 클라이언트 선언(params[:game], enum allowlist)**을
# game_type 으로 기록한다 — md §69 의 "서버 결정 영속화" 이상과의 **의도적 편차**(저위험 자기이득:
# distinct_games 를 스스로 빨리 채우는 것뿐). book(책 소개 대결)은 라우트가 서버에서 game_type 을 확정한다.
#
# 게임 재구성 Phase 1: 표면(라우트/카탈로그/뷰)은 quiz·whoami·book 3종만 남았다. **enum 정수는 재배열하지
# 않는다** — vocab(2)은 hard-delete(데이터·enum 키 제거, 정수 2 gap), classic(1)은 soft-deprecate(값·과거
# 기록 보존, 새 표면 없음 — 옛 기록이 정상 퀴즈 플레이라 유지). 정수 2 gap 은 의도된 것이다.
class GamePlay < ApplicationRecord
  # 학생 게임 원장 game_type. 정수 매핑 고정(vocab:2 hard-delete, gap 유지; classic:1 soft-deprecate).
  enum :game_type, { quiz: 0, classic: 1, whoami: 3, book: 4 }

  belongs_to :user
  belongs_to :book, optional: true

  validates :game_type, presence: true
  validates :played_on, presence: true
end
