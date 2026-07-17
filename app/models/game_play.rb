# 게임 완료 활동 원장 1행(monster_unlocks.md §게임 판정, Phase 3B). 몬스터 해금 지표
# game_plays/distinct_games/game_books 의 서버 권위 소스.
#
# game_type 신뢰 경계: quiz·classic 은 같은 mcq 콘텐츠(Quiz 행)를 공유해 서버가 Quiz 행만으론
# 두 표면을 권위적으로 구분할 수 없다(monster_unlocks.md §69). 그래서 퀴즈 4종은 **검증된
# 클라이언트 선언(params[:game], 5값 allowlist)**을 game_type 으로 기록한다 — md §69 의 "서버
# 결정 영속화" 이상과의 **의도적 편차**(저위험 자기이득: distinct_games 를 스스로 빨리 채우는 것뿐).
# book(책 소개 대결)은 라우트가 서버에서 game_type 을 확정하므로 신뢰 경계 밖이다.
class GamePlay < ApplicationRecord
  # 학생 게임 카탈로그 5종(monster_unlocks.md §게임 판정). 정수 매핑 고정.
  enum :game_type, { quiz: 0, classic: 1, vocab: 2, whoami: 3, book: 4 }

  belongs_to :user
  belongs_to :book, optional: true

  validates :game_type, presence: true
  validates :played_on, presence: true
end
