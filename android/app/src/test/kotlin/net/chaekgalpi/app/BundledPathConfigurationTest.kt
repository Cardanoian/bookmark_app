package net.chaekgalpi.app

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * APK 에 번들된 Path Configuration 의 계약 검증.
 *
 * 이 파일은 **원격 설정을 못 받았을 때의 유일한 폴백**이다. 여기가 깨지면 앱은 목적지 Fragment 를
 * 찾지 못해 첫 화면부터 뜨지 않는데, 원격이 살아 있는 동안에는 그 사실이 드러나지 않는다.
 *
 * 서버 쪽 `native_configuration_test.rb` 가 같은 파일을 Ruby 로 검사하지만, **정규식은 그것만으로
 * 부족하다** — 실제 매칭은 Android 가 Java/Kotlin 정규식으로 한다. Ruby 에서 유효한 패턴이 Java 에서
 * 예외를 던지면 앱에서는 그 규칙이 조용히 사라진다(오류도 로그도 없다). 그래서 여기서 컴파일까지 한다.
 */
class BundledPathConfigurationTest {

    private val config: JSONObject by lazy {
        // JVM 단위 테스트의 작업 디렉터리는 모듈 루트(app/)다. 저장소 루트에서 돌리는 경우도 받아 준다.
        val candidates = listOf(
            File("src/main/assets/json/path_configuration.json"),
            File("android/app/src/main/assets/json/path_configuration.json")
        )
        val file = candidates.firstOrNull { it.exists() }
            ?: error("번들 path configuration 을 찾지 못했다: ${candidates.joinToString { it.absolutePath }}")
        JSONObject(file.readText())
    }

    private fun rules(): List<JSONObject> {
        val array = config.getJSONArray("rules")
        return (0 until array.length()).map { array.getJSONObject(it) }
    }

    private fun JSONObject.patterns(): List<String> {
        val array = getJSONArray("patterns")
        return (0 until array.length()).map { array.getString(it) }
    }

    private fun JSONObject.properties(): JSONObject = optJSONObject("properties") ?: JSONObject()

    /** Hotwire Android 의 매칭 의미(부분 일치)를 그대로 흉내 낸다. */
    private fun matches(pattern: String, path: String) = Regex(pattern).containsMatchIn(path)

    @Test fun `모든 패턴이 Java 정규식으로 컴파일된다`() {
        // Ruby 쪽 테스트가 잡지 못하는 구멍이다. 컴파일에 실패하면 그 규칙만 조용히 죽는다.
        rules().forEach { rule ->
            rule.patterns().forEach { pattern ->
                try {
                    Regex(pattern)
                } catch (e: Exception) {
                    throw AssertionError("패턴 '$pattern' 이 Java 정규식으로 컴파일되지 않는다: ${e.message}")
                }
            }
        }
    }

    @Test fun `첫 규칙이 모든 경로를 받고 목적지를 준다`() {
        // Hotwire 는 첫 규칙을 기본값으로 삼고 뒤 규칙이 이를 상속한다. uri 가 없으면 앱이 뜨지 않는다.
        val first = rules().first()
        assertTrue("첫 규칙은 모든 경로를 받아야 한다", first.patterns().contains(".*"))
        assertEquals("hotwire://fragment/web", first.properties().getString("uri"))
    }

    @Test fun `당겨서 새로고침이 꺼져 있다`() {
        // 장문 독후감 작성 중 당겨서 새로고침이 입력을 날리는 사고를 막는다(계획 §4.3).
        assertFalse(rules().first().properties().getBoolean("pull_to_refresh_enabled"))
    }

    @Test fun `로그인 화면과 루트는 스택을 초기화한다`() {
        // replace_root 가 빠지면 로그아웃 뒤에도 이전 화면이 뒤로가기로 되살아난다(계획 D9).
        listOf("/", "/session/new").forEach { path ->
            val replaced = rules().any { rule ->
                rule.properties().optString("presentation") == "replace_root" &&
                    rule.patterns().any { matches(it, path) }
            }
            assertTrue("$path 가 replace_root 규칙에 걸려야 한다", replaced)
        }
    }

    @Test fun `다운로드 규칙은 MIME 을 함께 준다`() {
        // 라우팅으로 잡은 다운로드는 응답 헤더가 없어 URL 조각밖에 단서가 없다.
        // 확장자 없는 이름으로 저장되면 기기에서 열리지 않는다.
        rules().filter { it.properties().optBoolean("download") }.forEach { rule ->
            assertTrue(
                "download 규칙 ${rule.patterns()} 에 download_mime 이 없다",
                rule.properties().optString("download_mime").isNotBlank()
            )
        }
    }

    @Test fun `평범한 화면 경로가 다운로드로 새지 않는다`() {
        // `\.pdf$` 같은 패턴이 과하게 넓어지면 화면 이동이 저장 대화상자로 바뀐다.
        val downloadRules = rules().filter { it.properties().optBoolean("download") }
        listOf("/", "/session/new", "/reports", "/reports/1", "/monsters", "/teacher/prints")
            .forEach { path ->
                val leaked = downloadRules.any { rule -> rule.patterns().any { matches(it, path) } }
                assertFalse("화면 경로 $path 가 다운로드로 처리되면 안 된다", leaked)
            }
    }

    @Test fun `호환성 계약 키가 있다`() {
        // 서버가 최소 지원 버전을 올려 구 APK 를 안내로 유도하는 경로(계획 A-3).
        val settings = config.getJSONObject("settings")
        assertTrue("schema_version 이 있어야 한다", settings.has("schema_version"))
        assertTrue(
            "minimum_supported_version 이 있어야 한다",
            settings.optString("minimum_supported_version").isNotBlank()
        )
    }
}
