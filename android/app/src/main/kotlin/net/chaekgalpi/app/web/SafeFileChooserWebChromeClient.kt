package net.chaekgalpi.app.web

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebView
import dev.hotwire.core.turbo.session.Session
import dev.hotwire.core.turbo.webview.HotwireWebChromeClient

/**
 * core 의 파일 선택 동작(카메라 + 사진 선택기)을 **그대로 쓰되**, WebView 콜백 계약만 지켜 주는 얇은 층.
 *
 * 왜 core 를 대체하지 않는가: `FileChooserDelegate` 가 촬영·선택·캐시 복사·FileProvider 를 이미
 * 전부 구현하고 있고(계획 §M.3), OCR 폼의 `accept` 가 이미지 와일드카드(`image` 뒤에 `*`)라서
 * 시스템 선택기가 **카메라와 사진 선택기를 둘 다** 제시하는 것을 에뮬레이터에서 실측했다.
 * 다시 만들 이유가 없다.
 *
 * 여기서 고치는 것은 [FileChooserCallbackGuard] 가 설명하는 두 가지뿐이다 —
 * **UI 스레드 전달**과 **정확히 한 번 응답**.
 *
 * ### 선택기가 이미 떠 있는데 새 요청이 오면
 * 이전 콜백을 취소로 닫아 버리지 않는다. 그건 이미 시스템 선택기가 붙들고 있는 요청이고,
 * 곧 정상적으로 응답된다. 대신 **새 요청을 즉시 "선택 없음"으로 닫는다.** 그래야 모든 콜백이
 * 정확히 한 번씩 응답되고, 선택기 Activity 가 겹쳐 쌓이지 않는다.
 */
class SafeFileChooserWebChromeClient(session: Session) : HotwireWebChromeClient(session) {

    private val mainHandler = Handler(Looper.getMainLooper())

    /** 지금 시스템 선택기가 붙들고 있는 요청. 응답되면 [FileChooserCallbackGuard.isPending] 이 false 가 된다. */
    private var inFlight: FileChooserCallbackGuard<Array<Uri>>? = null

    override fun onShowFileChooser(
        webView: WebView,
        filePathCallback: ValueCallback<Array<Uri>>,
        fileChooserParams: WebChromeClient.FileChooserParams
    ): Boolean {
        val guard = FileChooserCallbackGuard<Array<Uri>>(
            isMainThread = { Looper.myLooper() == Looper.getMainLooper() },
            postToMainThread = { mainHandler.post(it) },
            deliver = { uris -> filePathCallback.onReceiveValue(uris) }
        )

        if (inFlight?.isPending == true) {
            // 선택기가 이미 떠 있다. 새 요청은 지금 자리에서 닫는다(미완 콜백을 남기지 않는다).
            guard.receive(null)
            return true
        }

        inFlight = guard
        val opened = super.onShowFileChooser(
            webView,
            ValueCallback { uris -> guard.receive(uris) },
            fileChooserParams
        )
        // core 는 선택기를 못 열면 스스로 취소를 보내지만, 그 경로가 바뀌어도 콜백이 미완으로 남지 않게 한다.
        if (!opened) guard.receive(null)
        return opened
    }
}
