package net.chaekgalpi.app.bridge

import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import net.chaekgalpi.app.MainActivity
import net.chaekgalpi.app.R

/**
 * 성장카드 PNG 저장(계획 §7.4).
 *
 * 웹의 `<a download>` + Canvas data URL 은 Android WebView 에서 아무 일도 하지 않는다.
 * 브라우저에서는 기존 동작을 그대로 두고(`save-image` 컨트롤러가 로드되지 않는다),
 * 앱에서만 이 컴포넌트가 받아 사용자가 고른 위치에 직접 쓴다.
 *
 * 저장 경로는 인증 다운로드와 **같은 창구**(`DownloadCoordinator`)를 쓴다. 파일명 정규화와
 * 실패 시 0바이트 파일 정리 규칙이 한 곳에만 있어야 하기 때문이다.
 */
class SaveImageComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        when (message.event) {
            "save" -> save(message)
            else -> Unit // 모르는 이벤트는 무시한다. 웹이 앞서 나가도 앱이 깨지지 않는다.
        }
    }

    private fun save(message: Message) {
        val activity = delegate.destination.fragment.activity as? MainActivity ?: return

        when (val payload = ImagePayload.parse(message.jsonData)) {
            is ImagePayload.Result.Valid ->
                activity.downloads.saveBytes(
                    bytes = payload.bytes,
                    mimeType = "image/png",
                    suggestedName = payload.fileName
                )

            // 실패 사유를 화면에 자세히 쓰지 않는다 — 학생·교사에게 base64 길이는 의미가 없다.
            // 원인 추적은 웹 쪽 코드 검토로 하고, 여기서는 조용히 실패하지만 알리기는 한다.
            is ImagePayload.Result.Invalid -> activity.toastDownloadFailure(R.string.download_failed)
        }
    }
}
