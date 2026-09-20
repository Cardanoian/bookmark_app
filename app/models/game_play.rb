# 게임 완료 활동 원장 1행(monster_unlocks.md §게임 판정, Phase 3B). 몬스터 해금 지표
# game_plays/distinct_games/game_books 의 서버 권위 소스.
#
# game_type 신뢰 경계(BUG_FIX_PLAN F4, 2026-09-20): **게임 종류는 서버가 정한다.** 퀴즈 표면(quiz·whoami)은
# 검증한 퀴즈 유형(`Quiz#play_game_type` — 콘텐츠축과 문항 구성)에서, book(책 소개 대결)·sequel(뒷이야기)은
# 그 글을 저장하는 전용 라우트에서 확정한다. 예전에는 퀴즈 표면을 서버가 구분할 수 없다고 보고 클라이언트
# 선언(params[:game], enum allowlist)을 그대로 기록했는데, 객관식 제출에 game 값만 바꿔 보내면 글 한 줄 없이
# book·sequel·classic·whoami 완료가 쌓여 distinct_games 해금을 채울 수 있었다. 지금은 quiz·whoami 가
# 콘텐츠축으로 구분되므로 요청값을 쓰지 않는다.
#
# 게임 재구성 Phase 1: 표면(라우트/카탈로그/뷰)은 quiz·whoami·book 3종만 남았다. **enum 정수는 재배열하지
# 않는다** — vocab(2)은 hard-delete(데이터·enum 키 제거, 정수 2 gap), classic(1)은 soft-deprecate(값·과거
# 기록 보존, 새 표면 없음 — 옛 기록이 정상 퀴즈 플레이라 유지. **새로 기록하는 경로는 없다**). 정수 2 gap 은 의도된 것이다.
# 게임 재구성 Phase 2: sequel(5) additive 추가 → **활성 4종=quiz·whoami·book·sequel**(classic soft-deprecate).
# sequel(뒷이야기 이어쓰기)은 book 처럼 book_id 있는 플레이라 기존 부분 유니크 인덱스로 일일 dedup 된다.
class GamePlay < ApplicationRecord
  # 학생 게임 원장 game_type. 정수 매핑 고정(vocab:2 hard-delete, gap 유지; classic:1 soft-deprecate; sequel:5 추가).
  enum :game_type, { quiz: 0, classic: 1, whoami: 3, book: 4, sequel: 5 }

  belongs_to :user
  belongs_to :book, optional: true

  validates :game_type, presence: true
  validates :played_on, presence: true

  # 오늘(Asia/Seoul)의 완료 1행을 멱등 기록한다. 새로 기록했으면 그 행을, 같은 학생·게임·(책)·일자의
  # 기존 행과 부딪히면(부분 유니크 인덱스 2종) nil 을 돌려준다 — 호출부는 새 행일 때만 미션·챌린지·몬스터
  # 해금을 다시 평가한다. 학생만 기록한다(도감은 학생 전용). enum 밖 game_type 은 기록하지 않는다.
  #
  # 삽입을 savepoint 로 감싼다(requires_new). 퀴즈 제출은 attempt 확정·포인트 적립과 **같은 트랜잭션**에서
  # 이 메서드를 부르는데(Games::QuizPlay), 유니크 충돌이 바깥 트랜잭션까지 되돌리면 같은 날 두 번째 판의
  # 확정·적립이 통째로 사라진다. 트랜잭션 밖에서 부르면(book·sequel) 평범한 단독 트랜잭션이다.
  def self.record_daily!(user:, game_type:, book_id:)
    game_type = game_type.to_s
    return nil unless user&.student? && game_types.key?(game_type)

    transaction(requires_new: true) do
      create!(user: user, game_type: game_type, book_id: book_id,
              played_on: Time.current.in_time_zone("Asia/Seoul").to_date)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
