package net.chaekgalpi.app.downloads

import java.io.UnsupportedEncodingException
import java.net.URI
import java.net.URLDecoder
import java.util.Locale

/**
 * 서버가 준 `Content-Disposition` 에서 저장 파일명을 뽑아 **안전하게 정규화**한다.
 *
 * 파일명은 서버가 준 값이지만 그대로 믿지 않는다. 사용자가 고른 폴더에 쓰는 것은 SAF 가 처리하므로
 * 경로 탈출 자체는 불가능하지만, `../../` 나 개행이 섞인 이름은 목록에서 오해를 부르고 일부 파일 관리
 * 앱에서 깨진다. 계획 §7.3-6 "Content-Disposition 파일명을 파싱하고 경로문자를 제거해 정규화한다".
 *
 * Android 의존성이 없는 순수 코드라 JVM 단위 테스트로 전수 검증한다.
 */
object DownloadNaming {

    private const val FALLBACK = "download"

    /** 파일명 길이 상한. 확장자를 남기고 앞부분만 자른다. */
    private const val MAX_LENGTH = 100

    /** 확장자가 없을 때 MIME 으로 보완할 수 있는 최소 목록(이 앱이 실제로 내려주는 것들). */
    private val EXTENSION_BY_MIME = mapOf(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" to "xlsx",
        "text/csv" to "csv",
        "application/pdf" to "pdf",
        "image/jpeg" to "jpg",
        "image/png" to "png"
    )

    /**
     * @param contentDisposition 응답 헤더 원문. 있으면 가장 정확하므로 최우선이다.
     * @param url 다운로드 URL. 마지막 후보.
     * @param mimeType 응답의 MIME. 확장자가 없을 때만 참고한다.
     * @param suggested Path Configuration 의 `download_filename`. 라우팅으로 잡은 다운로드는
     *   아직 응답 헤더가 없어서 URL 마지막 조각(`reports_xlsx` 처럼 확장자 없는 이름)밖에 없다.
     *   서버가 원하는 이름을 원격 설정으로 내려 줄 수 있게 한다.
     */
    fun fileName(
        contentDisposition: String?,
        url: String?,
        mimeType: String?,
        suggested: String? = null
    ): String {
        val raw = fromDisposition(contentDisposition)
            ?: suggested?.takeIf { it.isNotBlank() }
            ?: fromUrl(url)

        val sanitized = sanitize(raw)
        val base = sanitized.ifBlank { FALLBACK }

        return withExtension(base, mimeType)
    }

    // ── Content-Disposition 파싱 ────────────────────────────────────────────────

    private fun fromDisposition(header: String?): String? {
        if (header.isNullOrBlank()) return null

        // RFC 6266 의 `filename*` 를 먼저 본다. Rails send_data 는 filename 과 filename* 을 함께 보내며,
        // 한글 파일명은 filename* 쪽에만 온전히 담긴다.
        extended(header)?.let { return it }

        // filename="..." 또는 filename=토큰
        val quoted = Regex("""filename\s*=\s*"([^"]*)"""", RegexOption.IGNORE_CASE).find(header)
        if (quoted != null) return quoted.groupValues[1]

        val bare = Regex("""filename\s*=\s*([^;]+)""", RegexOption.IGNORE_CASE).find(header)
        return bare?.groupValues?.get(1)?.trim()
    }

    /** `filename*=UTF-8''%ED%95%99%EC%83%9D.csv` 형태. charset''value 에서 value 를 퍼센트 디코딩한다. */
    private fun extended(header: String): String? {
        val match = Regex("""filename\*\s*=\s*([^;]+)""", RegexOption.IGNORE_CASE).find(header)
            ?: return null

        val value = match.groupValues[1].trim().trim('"')
        val parts = value.split("'", limit = 3)
        // charset'language'value 3조각이 아니면 확장 형식이 아니다.
        if (parts.size < 3) return null

        val charset = parts[0].ifBlank { "UTF-8" }
        return try {
            URLDecoder.decode(parts[2], charset)
        } catch (e: UnsupportedEncodingException) {
            null
        } catch (e: IllegalArgumentException) {
            // 잘못된 퍼센트 인코딩. 조용히 다음 후보로 넘어간다.
            null
        }
    }

    private fun fromUrl(url: String?): String? {
        if (url.isNullOrBlank()) return null

        val path = try {
            URI(url).path
        } catch (e: Exception) {
            null
        } ?: return null

        val last = path.substringAfterLast('/')
        if (last.isBlank()) return null

        return try {
            URLDecoder.decode(last, "UTF-8")
        } catch (e: Exception) {
            last
        }
    }

    // ── 정규화 ─────────────────────────────────────────────────────────────────

    private fun sanitize(name: String?): String {
        if (name == null) return ""

        // 경로 조각을 통째로 버린다. "../../etc/passwd" → "passwd"
        var result = name.substringAfterLast('/').substringAfterLast('\\')

        // 제어문자(개행·NUL 포함)와 파일 관리 앱이 싫어하는 문자를 밑줄로 바꾼다.
        result = result.map { ch ->
            when {
                ch.isISOControl() -> '_'
                ch in "\"*:<>?|" -> '_'
                else -> ch
            }
        }.joinToString("")

        // 앞뒤 공백과 점을 떨어낸다. ".", ".." 는 이 단계에서 빈 문자열이 된다.
        result = result.trim().trim('.').trim()

        if (result.isBlank()) return ""

        return truncate(result)
    }

    /** 확장자를 살리면서 길이를 줄인다. */
    private fun truncate(name: String): String {
        if (name.length <= MAX_LENGTH) return name

        val dot = name.lastIndexOf('.')
        // 확장자가 없거나 비정상적으로 길면 그냥 앞에서 자른다.
        if (dot <= 0 || name.length - dot > 10) return name.take(MAX_LENGTH)

        val extension = name.substring(dot)
        return name.take(MAX_LENGTH - extension.length) + extension
    }

    /** 확장자가 없으면 MIME 으로 보완한다. 이미 있으면 서버가 준 것을 존중한다. */
    private fun withExtension(name: String, mimeType: String?): String {
        if (name.contains('.')) return name

        val normalized = mimeType?.substringBefore(';')?.trim()?.lowercase(Locale.ROOT)
        val extension = EXTENSION_BY_MIME[normalized] ?: return name

        return "$name.$extension"
    }
}
