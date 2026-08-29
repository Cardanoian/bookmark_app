package net.chaekgalpi.app

import net.chaekgalpi.app.bridge.ImagePayload
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/**
 * `save-image` 브리지가 웹에서 받는 값의 경계 검증.
 * 웹이 보낸 값이라 형식·크기를 앱이 다시 확인한다(계획 §7.4 payload 상한).
 */
class ImagePayloadTest {

    private fun encode(bytes: ByteArray) = Base64.getEncoder().encodeToString(bytes)

    @Test fun `정상 payload 를 바이트로 되돌린다`() {
        val original = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47)  // PNG 시그니처
        val json = """{"filename":"성장카드_이도현.png","base64":"${encode(original)}"}"""

        val result = ImagePayload.parse(json)
        assertTrue(result is ImagePayload.Result.Valid)
        result as ImagePayload.Result.Valid

        assertEquals("성장카드_이도현.png", result.fileName)
        assertArrayEquals(original, result.bytes)
    }

    @Test fun `파일명이 없어도 바이트는 살린다`() {
        // 파일명 정규화는 저장 단계의 책임이라 여기서 지어내지 않는다.
        val json = """{"base64":"${encode(byteArrayOf(1, 2, 3))}"}"""
        assertTrue(ImagePayload.parse(json) is ImagePayload.Result.Valid)
    }

    @Test fun `JSON 이 아니면 거부한다`() {
        assertEquals(ImagePayload.Result.Invalid.Malformed, ImagePayload.parse("not json"))
        assertEquals(ImagePayload.Result.Invalid.Malformed, ImagePayload.parse(""))
        assertEquals(ImagePayload.Result.Invalid.Malformed, ImagePayload.parse(null))
    }

    @Test fun `base64 키가 없으면 거부한다`() {
        assertEquals(
            ImagePayload.Result.Invalid.Malformed,
            ImagePayload.parse("""{"filename":"a.png"}""")
        )
    }

    @Test fun `base64 가 아니면 거부한다`() {
        assertEquals(
            ImagePayload.Result.Invalid.NotBase64,
            ImagePayload.parse("""{"base64":"!!!not base64!!!"}""")
        )
    }

    @Test fun `빈 이미지는 거부한다`() {
        // 빈 바이트의 base64 는 빈 문자열이라 키 누락과 같은 자리에서 걸린다.
        assertEquals(
            ImagePayload.Result.Invalid.Malformed,
            ImagePayload.parse("""{"base64":""}""")
        )
    }

    @Test fun `상한을 넘으면 거부한다`() {
        val tooBig = encode(ByteArray(ImagePayload.MAX_BYTES + 1))
        assertEquals(ImagePayload.Result.Invalid.TooLarge, ImagePayload.parse("""{"base64":"$tooBig"}"""))
    }

    @Test fun `상한 경계값은 통과한다`() {
        val atLimit = encode(ByteArray(ImagePayload.MAX_BYTES))
        assertTrue(ImagePayload.parse("""{"base64":"$atLimit"}""") is ImagePayload.Result.Valid)
    }

    @Test fun `성장카드 크기는 상한에 한참 못 미친다`() {
        // 320x220 PNG 는 수 KB 다. 상한이 실사용을 막지 않는지 눈으로 확인해 둔다.
        assertTrue("상한 512KB", ImagePayload.MAX_BYTES >= 512 * 1024)
    }
}
