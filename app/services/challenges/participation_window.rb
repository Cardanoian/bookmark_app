module Challenges
  # 챌린지 활동을 세는 기간 창(참여 이후 ~ 종료일 끝). **진행도와 순위가 같은 규칙을 쓰도록** 한곳에 둔다.
  #
  # 2026-09-16 전까지 순위(`RankingBoard#challenge_ranking`)는 다른 규칙을 썼다 — 참여할 때 세션 쿠키에
  # 표를 남기고 그 뒤 **첫 글 한 편**에만 `reports.challenge_id` 를 달아 그 수를 셌다. 참여 1회당 1편이라
  # 순위가 사실상 전원 동률이었고, 참여 버튼을 다시 누르면 표가 다시 생겨 여러 편이 붙었으며, 쿠키라서
  # 동시 요청이 이미 쓴 표를 되살리는 경합도 있었다. 지금은 양쪽 모두 이 창으로 센다.
  module ParticipationWindow
    ZONE = ActiveSupport::TimeZone["Asia/Seoul"]

    module_function

    # 독후감 제출 시각(datetime) 비교용 창. 하한은 창 시작 00:00 과 참여 시각 중 **늦은 쪽**이라
    # 참여 전에 낸 글은 세지 않고, 상한은 종료일 다음날 00:00(배타)이다. 종료일이 없으면 상한 없음.
    def time_range(challenge, joined_at)
      [ start_at(challenge), joined_at ].compact.max...upper_at(challenge)
    end

    def start_at(challenge)
      s = challenge.window_start
      s && ZONE.local(s.year, s.month, s.day)
    end

    def upper_at(challenge)
      e = challenge.window_end
      e && ZONE.local(e.year, e.month, e.day) + 1.day
    end

    # 참여일(Asia/Seoul) — `game_plays.played_on`(date) 비교용 하한. 참여 당일에 먼저 플레이한
    # 게임까지 인정되는 근사이며, 미션의 assigned_on clamp 와 같은 관용구다.
    def joined_on(joined_at)
      joined_at&.in_time_zone(ZONE)&.to_date
    end
  end
end
