package net.chaekgalpi.app.web

import java.util.concurrent.atomic.AtomicBoolean

/**
 * WebView 파일 선택 콜백을 **정확히 한 번, UI 스레드에서** 전달하도록 감싸는 순수 로직.
 *
 * `WebChromeClient.onShowFileChooser` 로 받은 `ValueCallback` 은 WebView 계약상 UI 스레드에서
 * 정확히 한 번 응답해야 한다. Hotwire Native core 1.3.1 은 두 가지를 지키지 않는다(1.3.1 바이트코드 실측).
 *
 *  · `BrowseFilesDelegate` 의 코루틴 컨텍스트가 IO 디스패처라, 갤러리에서 고른 파일을 캐시에 복사한 뒤
 *    **IO 스레드에서** 콜백을 부른다. `FileChooserDelegate.sendResult` 에 메인 스레드 복귀가 없다.
 *  · `FileChooserDelegate.onShowFileChooser` 는 새 요청이 오면 `uploadCallback` 을 그냥 덮어쓴다.
 *    이전 콜백은 응답되지 않은 채 버려진다.
 *
 * 에뮬레이터(Android 15 / WebView 124)에서 사진 선택 중 **프로세스 abort** 를 1회 실측했고,
 * 툼스톤 스택이 `FileChooserDelegate.sendResult → ValueCallback.onReceiveValue → JNI → SIGTRAP`
 * 이었다. 재현율이 낮아(약 12회 중 1회) 이 감시자가 그 크래시를 없앤다고 단정하지는 않는다.
 * 다만 위 두 계약 위반을 제거하는 것은 어느 가설에서도 안전한 방향이다.
 *
 * 라이브러리 타입에 의존하지 않아 JVM 단위 테스트로 전수 검증한다.
 */
class FileChooserCallbackGuard<T>(
    private val isMainThread: () -> Boolean,
    private val postToMainThread: (() -> Unit) -> Unit,
    private val deliver: (T?) -> Unit
) {

    private val delivered = AtomicBoolean(false)

    /** 아직 응답하지 않았는가. 새 선택 요청을 어떻게 처리할지 판단하는 데 쓴다. */
    val isPending: Boolean
        get() = !delivered.get()

    /**
     * 결과를 전달한다. 두 번째 호출부터는 **조용히 무시**한다 —
     * WebView 콜백에 두 번 응답하면 Chromium 이 프로세스를 죽인다.
     *
     * 취소는 `null` 로 들어오며, 취소 역시 정확히 한 번만 전달된다.
     */
    fun receive(value: T?) {
        if (!delivered.compareAndSet(false, true)) return
        if (isMainThread()) deliver(value) else postToMainThread { deliver(value) }
    }
}
