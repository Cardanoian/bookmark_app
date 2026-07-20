require "test_helper"

# 게임 재구성 Phase 1(로스터 정리) 검증(계획서 §2·§6): 고전(classic) 표면 통합(→quiz)·어휘 낚시(vocab)
# hard-delete 후 로스터가 quiz·whoami·book 3종으로 정리됐는지, 제거된 표면의 라우트/카탈로그가 사라졌는지,
# game_type enum 정수 매핑이 재배열 없이 보존됐는지를 회귀 검증한다.
class GamesRosterTest < ActionDispatch::IntegrationTest
  # ── ① 제거된 표면의 온디맨드 play 라우트가 더는 존재하지 않는다 ──────────────
  test "classic and vocab on-demand play routes no longer exist" do
    %w[/games/classic/play /games/vocab/play].each do |path|
      assert_raises(ActionController::RoutingError, "#{path} 는 더는 라우팅되면 안 된다") do
        Rails.application.routes.recognize_path(path, method: :get)
      end
    end
  end

  # 살아있는 표면(quiz·whoami)의 play 라우트는 그대로 인식된다(회귀 반대 방향).
  test "quiz and whoami on-demand play routes still resolve" do
    assert_equal({ controller: "games/quiz", action: "play" },
                 Rails.application.routes.recognize_path("/games/quiz/play", method: :get))
    assert_equal({ controller: "games/whoami", action: "play" },
                 Rails.application.routes.recognize_path("/games/whoami/play", method: :get))
  end

  # ── ② 카탈로그(CATALOG)에 classic·vocab 이 없고 3종만 남는다 ──────────────────
  test "the game catalog contains only quiz, whoami and book" do
    catalog = Games::BaseController::CATALOG
    assert_equal %w[quiz whoami book].sort, catalog.keys.sort
    assert_not catalog.key?("classic"), "classic 은 카탈로그에서 제거됐다(→quiz 통합)"
    assert_not catalog.key?("vocab"), "vocab 은 카탈로그에서 제거됐다(hard-delete)"
  end

  # ── ③ game_type enum 은 vocab 을 빼되 나머지 정수를 재배열하지 않는다 ─────────
  test "GamePlay game_type enum drops vocab and preserves quiz(0)/classic(1)/whoami(3)/book(4)" do
    assert_equal({ "quiz" => 0, "classic" => 1, "whoami" => 3, "book" => 4 }, GamePlay.game_types)
  end
end
