package net.chaekgalpi.app.downloads

import android.webkit.CookieManager
import net.chaekgalpi.app.navigation.NativeRouting
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

/**
 * 로그인 세션이 필요한 파일(교사·관리자 CSV, 동의서 PDF)을 사용자가 고른 위치로 직접 내려받는다.
 *
 * **`DownloadManager` 를 쓰지 않는 이유**: 시스템 다운로드는 공용 Downloads 폴더에 자동 저장한다.
 * 이 앱의 CSV 에는 학생 이름과 학급 통계가 들어가므로, 저장 위치를 사용자가 고르게 하고
 * 앱이 직접 스트리밍한다(계획 §7.3).
 *
 * **리다이렉트를 직접 따라가는 이유**: `HttpURLConnection` 의 자동 추적을 쓰면 최종 목적지를 검사할
 * 기회가 없다. 신뢰 호스트가 외부로 302 를 주는 순간 Rails 세션 쿠키가 그대로 따라간다.
 * 매 홉마다 [NativeRouting.allowsCredentialedRequest] 로 다시 검사한다.
 *
 * **로그를 남기지 않는다**: URL·쿠키·본문 어느 것도 출력하지 않는다(아동 PII·세션).
 */
class AuthenticatedDownloader(
    private val developmentOrigin: String? = null,
    private val cookieProvider: (String) -> String? = { CookieManager.getInstance().getCookie(it) }
) {

    sealed interface Result {
        data class Success(val bytes: Long) : Result
        data class Failure(val reason: Reason) : Result
    }

    enum class Reason {
        /** 신뢰하지 않는 호스트. 쿠키를 실을 수 없다. */
        UntrustedHost,

        /** 401·403. 세션이 끊겼거나 권한이 없다. */
        Unauthorized,

        /** 그 밖의 HTTP 오류·네트워크 실패. */
        Network,

        /** 저장 대상에 쓰지 못했다. */
        Storage,

        /** 리다이렉트가 너무 많다. 루프로 본다. */
        TooManyRedirects
    }

    fun download(url: String, userAgent: String?, sink: OutputStream): Result {
        var current = url

        repeat(MAX_REDIRECTS) {
            if (!NativeRouting.allowsCredentialedRequest(current, developmentOrigin)) {
                return Result.Failure(Reason.UntrustedHost)
            }

            val connection = try {
                open(current, userAgent)
            } catch (e: Exception) {
                return Result.Failure(Reason.Network)
            }

            try {
                when (val code = connection.responseCode) {
                    in 200..299 -> return stream(connection, sink)

                    HttpURLConnection.HTTP_MOVED_PERM,
                    HttpURLConnection.HTTP_MOVED_TEMP,
                    HttpURLConnection.HTTP_SEE_OTHER,
                    TEMPORARY_REDIRECT,
                    PERMANENT_REDIRECT -> {
                        val next = connection.getHeaderField("Location")
                            ?: return Result.Failure(Reason.Network)
                        current = resolve(current, next) ?: return Result.Failure(Reason.Network)
                    }

                    HttpURLConnection.HTTP_UNAUTHORIZED,
                    HttpURLConnection.HTTP_FORBIDDEN -> return Result.Failure(Reason.Unauthorized)

                    else -> {
                        @Suppress("UNUSED_EXPRESSION") code
                        return Result.Failure(Reason.Network)
                    }
                }
            } catch (e: Exception) {
                return Result.Failure(Reason.Network)
            } finally {
                connection.disconnect()
            }
        }

        return Result.Failure(Reason.TooManyRedirects)
    }

    private fun open(url: String, userAgent: String?): HttpURLConnection {
        val connection = URL(url).openConnection() as HttpURLConnection

        // 인증서 검증을 우회하지 않는다 — 기본 SSLSocketFactory 를 그대로 쓴다.
        connection.instanceFollowRedirects = false
        connection.connectTimeout = CONNECT_TIMEOUT_MS
        connection.readTimeout = READ_TIMEOUT_MS
        connection.requestMethod = "GET"

        // WebView 가 들고 있는 Rails 세션 쿠키를 그대로 쓴다. 앱은 쿠키를 따로 저장하지 않는다.
        cookieProvider(url)?.takeIf { it.isNotBlank() }?.let {
            connection.setRequestProperty("Cookie", it)
        }
        userAgent?.takeIf { it.isNotBlank() }?.let {
            connection.setRequestProperty("User-Agent", it)
        }

        return connection
    }

    private fun stream(connection: HttpURLConnection, sink: OutputStream): Result {
        return try {
            var total = 0L
            connection.inputStream.use { source ->
                val buffer = ByteArray(BUFFER_SIZE)
                while (true) {
                    val read = source.read(buffer)
                    if (read == -1) break
                    sink.write(buffer, 0, read)
                    total += read
                }
            }
            sink.flush()
            Result.Success(total)
        } catch (e: Exception) {
            // 읽기 실패인지 쓰기 실패인지 구분하지 않는다 — 사용자에게는 "저장하지 못했어요"로 같다.
            Result.Failure(Reason.Storage)
        }
    }

    /** 상대 Location 을 현재 URL 기준으로 해석한다. */
    private fun resolve(base: String, location: String): String? = try {
        URI(base).resolve(location).toString()
    } catch (e: Exception) {
        null
    }

    private companion object {
        const val MAX_REDIRECTS = 5
        const val CONNECT_TIMEOUT_MS = 15_000
        const val READ_TIMEOUT_MS = 30_000
        const val BUFFER_SIZE = 16 * 1024

        // HttpURLConnection 에 상수가 없는 코드들.
        const val TEMPORARY_REDIRECT = 307
        const val PERMANENT_REDIRECT = 308
    }
}
