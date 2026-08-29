package net.chaekgalpi.app.navigation

import android.widget.Toast
import dev.hotwire.core.turbo.visit.VisitProposal
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router
import net.chaekgalpi.app.R

/**
 * 기본 라우터 앞에 서서 [NativeRouting] 판정을 적용하는 어댑터.
 *
 * `Hotwire.registerRouteDecisionHandlers` 로 **첫 번째**에 등록해야 한다. Router 는 목록 순서대로
 * `matches` 를 물어 첫 번째 매칭 핸들러에 처리를 넘기므로, 뒤에 있으면 기본 핸들러가 먼저 가져간다.
 *
 * 판정 규칙 자체는 여기 없다 — [NativeRouting] 에 있고 순수 JVM 테스트로 고정돼 있다.
 * 이 클래스는 그 결과를 Hotwire 의 `Decision` 과 사용자 안내로 옮기기만 한다.
 *
 * @param developmentOrigin debug 로컬 서버 origin. release 에서는 null 이어야 한다.
 */
class TrustedUrlRouteDecisionHandler(
    private val developmentOrigin: String? = null
) : Router.RouteDecisionHandler {

    override val name = "chaekgalpi-trusted-url"

    override fun matches(
        proposal: VisitProposal,
        configuration: NavigatorConfiguration
    ): Boolean = NativeRouting.route(proposal.location, developmentOrigin) != NativeRouting.Route.Fallthrough

    override fun handle(
        proposal: VisitProposal,
        configuration: NavigatorConfiguration,
        activity: HotwireActivity
    ): Router.Decision = when (NativeRouting.route(proposal.location, developmentOrigin)) {
        // 기본 AppNavigationRouteDecisionHandler 와 같은 결정이다(실측: handle 이 NAVIGATE 만 반환).
        NativeRouting.Route.InApp -> Router.Decision.NAVIGATE

        NativeRouting.Route.Blocked -> {
            // URL 을 그대로 보여 주지 않는다 — 거부 대상에는 javascript: 본문처럼 길고 오해를 부르는
            // 문자열이 섞이고, 아동 사용자에게 의미도 없다.
            Toast.makeText(activity, R.string.link_blocked, Toast.LENGTH_SHORT).show()
            Router.Decision.CANCEL
        }

        // matches 가 false 를 준 경우라 실제로는 도달하지 않는다. 열지 않는 쪽으로 닫아 둔다.
        NativeRouting.Route.Fallthrough -> Router.Decision.CANCEL
    }
}
