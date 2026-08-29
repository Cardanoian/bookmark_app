package net.chaekgalpi.app.bridge

import android.content.Context
import android.print.PrintAttributes
import android.print.PrintManager
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import net.chaekgalpi.app.MainActivity
import net.chaekgalpi.app.R
import net.chaekgalpi.app.navigation.ChaekgalpiWebFragment

/**
 * Android 인쇄 / PDF 로 저장(계획 §7.5).
 *
 * 인쇄 레이아웃의 `window.print()` 는 Android WebView 에서 아무 일도 하지 않는다.
 * 브라우저에서는 인라인 핸들러가 그대로 남아 기존 인쇄가 동작하고(컨트롤러 미로드),
 * 앱에서는 이 컴포넌트가 현재 WebView 의 `PrintDocumentAdapter` 를 시스템 인쇄 화면에 넘긴다.
 *
 * 인쇄 대상은 **지금 보고 있는 화면 그대로**다. 인쇄 레이아웃의 `@media print` 규칙이
 * 그대로 적용되므로 툴바(`.no-print`)는 출력물에서 빠진다.
 */
class PrintComponent(
    name: String,
    private val delegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, delegate) {

    override fun onReceive(message: Message) {
        when (message.event) {
            "print" -> print()
            else -> Unit
        }
    }

    private fun print() {
        val fragment = delegate.destination.fragment
        val activity = fragment.activity as? MainActivity ?: return

        // WebView 는 Session 이 공유하고 붙어 있는 Fragment 만 참조를 갖는다.
        val webView = (fragment as? ChaekgalpiWebFragment)?.attachedWebView
            ?: return activity.toastDownloadFailure(R.string.print_failed)

        val printManager = activity.getSystemService(Context.PRINT_SERVICE) as? PrintManager
            ?: return activity.toastDownloadFailure(R.string.print_failed)

        // 인쇄 작업 이름은 저장 시 기본 파일명이 된다. 학생 이름을 앱이 지어내지 않고
        // 화면 제목(서버가 정한 값)을 그대로 쓴다.
        val jobName = webView.title?.takeIf { it.isNotBlank() } ?: activity.getString(R.string.app_name)

        try {
            printManager.print(
                jobName,
                webView.createPrintDocumentAdapter(jobName),
                PrintAttributes.Builder().build()
            )
        } catch (e: Exception) {
            // 인쇄 서비스가 없는 기기. 화면 상태는 그대로 두고 안내만 한다.
            activity.toastDownloadFailure(R.string.print_failed)
        }
    }
}
