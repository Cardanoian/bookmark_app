package net.chaekgalpi.app.downloads

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.widget.Toast
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import net.chaekgalpi.app.R
import net.chaekgalpi.app.navigation.NativeRouting
import java.util.concurrent.Executors

/**
 * 인증이 필요한 파일 저장의 단일 창구. **Activity 에 붙인다.**
 *
 * Fragment 가 아니라 Activity 스코프인 이유: 저장 위치를 고르는 동안(SAF 화면) 화면이 바뀌어도
 * 요청이 살아 있어야 하고, 다운로드 요청이 두 경로로 들어오기 때문이다.
 *  · 라우팅 — Path Configuration 이 `download: true` 로 표시한 경로(교사·관리자 CSV, 동의서 PDF)
 *  · WebView DownloadListener — 표시되지 않은 경로인데 WebView 가 첨부로 판정한 응답(안전망)
 *
 * **왜 라우팅으로 먼저 잡아야 하는가**: 표시가 없으면 Turbo 가 링크를 가로채 방문으로 처리하고,
 * CSV 응답은 HTML 이 아니라 `visitRequestFailedWithNonHttpStatusCode` 로 끝난다. 실측 결과 화면에는
 * "화면을 불러오지 못했어요"만 뜨고, **서버에는 다운로드 감사 로그가 남는다** — 받지도 않은 파일이
 * 내려받아진 것으로 기록되는 상태였다.
 */
class DownloadCoordinator(
    private val activity: AppCompatActivity,
    private val developmentOrigin: String?
) {

    private val downloader by lazy { AuthenticatedDownloader(developmentOrigin) }

    /** 다운로드 1건은 네트워크 → 파일 쓰기 한 줄이라 단일 스레드로 충분하다. */
    private val executor by lazy { Executors.newSingleThreadExecutor() }
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pending: Pending? = null

    private data class Pending(val url: String, val userAgent: String?)

    /**
     * ActivityResult 등록. **Activity 의 onCreate 에서 호출해야 한다**(STARTED 이후 등록은 예외).
     * `CreateDocument` 계약은 MIME 을 생성 시점에 고정해야 해서, MIME 이 응답마다 다른 여기서는
     * StartActivityForResult 로 Intent 를 직접 만든다.
     */
    private val launcher: ActivityResultLauncher<Intent> =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val request = pending
            pending = null

            val destination = result.data?.data
            // 사용자가 취소하면 아무 말 없이 끝낸다. 빈 파일도 남지 않는다(SAF 가 만들지 않았다).
            if (request == null || destination == null) return@registerForActivityResult

            start(request, destination)
        }

    /**
     * 저장 위치를 묻고 내려받는다.
     *
     * **묻는 것이 먼저인 이유**: 먼저 받아 두고 나중에 위치를 물으면 파일명은 정확해지지만,
     * 사용자가 취소해도 서버에는 CSV 다운로드 감사 로그가 남는다. 감사 원장이 "실제로 받아 간 것"과
     * 어긋나지 않도록 사용자가 저장을 확정한 뒤에만 요청을 보낸다.
     *
     * @param suggestedName Path Configuration 의 `download_filename`(라우팅 경로 전용).
     */
    fun request(
        url: String?,
        userAgent: String? = null,
        contentDisposition: String? = null,
        mimeType: String? = null,
        suggestedName: String? = null
    ) {
        if (url == null || !NativeRouting.allowsCredentialedRequest(url, developmentOrigin)) {
            // 신뢰하지 않는 호스트에는 세션 쿠키를 실을 수 없다. 조용히 삼키지 않고 이유를 알린다.
            toast(R.string.download_untrusted)
            return
        }

        pending = Pending(url, userAgent)

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType?.takeIf { it.isNotBlank() } ?: "*/*"
            putExtra(Intent.EXTRA_TITLE, DownloadNaming.fileName(contentDisposition, url, mimeType, suggestedName))
        }

        try {
            launcher.launch(intent)
        } catch (e: Exception) {
            // 문서 생성기를 가진 앱이 없는 기기.
            pending = null
            toast(R.string.download_failed)
        }
    }

    private fun start(request: Pending, destination: Uri) {
        val resolver = activity.applicationContext.contentResolver
        toast(R.string.download_started)

        executor.execute {
            val result = try {
                resolver.openOutputStream(destination)?.use { sink ->
                    downloader.download(request.url, request.userAgent, sink)
                } ?: AuthenticatedDownloader.Result.Failure(AuthenticatedDownloader.Reason.Storage)
            } catch (e: Exception) {
                AuthenticatedDownloader.Result.Failure(AuthenticatedDownloader.Reason.Storage)
            }

            if (result !is AuthenticatedDownloader.Result.Success) {
                // 실패하면 SAF 가 먼저 만들어 둔 0바이트 파일을 지운다.
                // 계획 §7.3 "빈 문서를 남기지 않는다".
                runCatching { DocumentsContract.deleteDocument(resolver, destination) }
            }

            mainHandler.post { announce(result) }
        }
    }

    private fun announce(result: AuthenticatedDownloader.Result) {
        val message = when (result) {
            is AuthenticatedDownloader.Result.Success -> R.string.download_saved
            is AuthenticatedDownloader.Result.Failure -> when (result.reason) {
                AuthenticatedDownloader.Reason.UntrustedHost -> R.string.download_untrusted
                AuthenticatedDownloader.Reason.Unauthorized -> R.string.download_unauthorized
                else -> R.string.download_failed
            }
        }
        toast(message)
    }

    /** Activity 가 이미 끝났으면 조용히 넘어간다(백그라운드 완료 시점의 크래시 방지). */
    private fun toast(messageId: Int) {
        if (activity.isFinishing || activity.isDestroyed) return
        Toast.makeText(activity, messageId, Toast.LENGTH_SHORT).show()
    }

    fun shutdown() {
        executor.shutdown()
    }
}
