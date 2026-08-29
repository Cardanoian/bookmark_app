package net.chaekgalpi.app.bridge

import org.json.JSONObject
import java.util.Base64

/**
 * `save-image` 브리지 메시지의 본문을 검증해 저장 가능한 바이트로 바꾼다.
 *
 * 웹에서 온 값이므로 그대로 믿지 않는다. 브리지는 우리 서버가 렌더한 화면만 붙지만,
 * 크기 상한과 형식 검사는 값이 어디서 오든 지켜야 하는 경계다(계획 §7.4
 * "Base64 payload 크기 상한을 둔다").
 *
 * Android 의존성을 쓰지 않는다 — `java.util.Base64` 는 API 26+ 이고 minSdk 는 28 이라
 * `android.util.Base64` 대신 이것을 써서 JVM 단위 테스트로 전수 검증한다.
 */
object ImagePayload {

    /**
     * 허용 상한 512KB. 성장카드는 320×220 PNG 라 실제로는 수 KB 다.
     * 상한을 두는 이유는 크기 자체보다, 브리지 메시지가 예상 밖으로 커지는 상황을 조용히
     * 통과시키지 않기 위해서다(메모리·저장 실패가 원인 불명으로 나타난다).
     */
    const val MAX_BYTES = 512 * 1024

    sealed interface Result {
        data class Valid(val fileName: String, val bytes: ByteArray) : Result {
            // ByteArray 는 참조 비교라 data class 의 equals 가 무의미하다. 테스트가 착각하지 않게 막는다.
            override fun equals(other: Any?): Boolean = this === other
            override fun hashCode(): Int = System.identityHashCode(this)
        }

        enum class Invalid : Result {
            /** JSON 이 아니거나 base64 키가 없다. */
            Malformed,

            /** base64 디코딩 실패. */
            NotBase64,

            /** 상한 초과. */
            TooLarge
        }
    }

    /**
     * @param json 브리지 메시지의 `jsonData` 원문.
     *   기대 형태: `{"filename": "성장카드_이도현.png", "base64": "iVBOR..."}`
     */
    fun parse(json: String?): Result {
        if (json.isNullOrBlank()) return Result.Invalid.Malformed

        val obj = try {
            JSONObject(json)
        } catch (e: Exception) {
            return Result.Invalid.Malformed
        }

        // 빈 문자열도 여기서 걸린다 — 빈 이미지와 키 누락은 "저장할 것이 없다"로 같다.
        val base64 = obj.optString("base64").takeIf { it.isNotBlank() }
            ?: return Result.Invalid.Malformed

        // 상한 검사를 디코딩 **전에** 한다. base64 는 원본의 4/3 이라 문자열 길이로 상한을 넘는지
        // 알 수 있고, 넘는 값을 굳이 메모리에 펼칠 이유가 없다.
        if (base64.length > MAX_BYTES / 3 * 4 + 4) return Result.Invalid.TooLarge

        val bytes = try {
            Base64.getDecoder().decode(base64)
        } catch (e: IllegalArgumentException) {
            return Result.Invalid.NotBase64
        }

        if (bytes.size > MAX_BYTES) return Result.Invalid.TooLarge

        // 파일명은 여기서 정하지 않고 저장 단계의 정규화에 맡긴다 — 규칙이 한 곳에만 있어야 한다.
        return Result.Valid(obj.optString("filename"), bytes)
    }
}
