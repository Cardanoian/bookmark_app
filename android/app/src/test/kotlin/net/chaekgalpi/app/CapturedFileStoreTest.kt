package net.chaekgalpi.app

import net.chaekgalpi.app.files.CapturedFileStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * 사진 찌꺼기 정리 검증.
 *
 * 두 방향으로 다 틀릴 수 있는 로직이다 — 너무 오래 두면 학생 손글씨 원본이 앱 저장소에 남고,
 * 너무 일찍 지우면 제출 직전의 사진이 사라져 업로드가 깨진다.
 */
class CapturedFileStoreTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val now = 1_800_000_000_000L

    private fun file(name: String, sizeBytes: Int, ageMillis: Long): File {
        val f = folder.newFile(name)
        if (sizeBytes > 0) f.writeBytes(ByteArray(sizeBytes))
        assertTrue(f.setLastModified(now - ageMillis))
        return f
    }

    @Test
    fun `보관 기간을 넘긴 사진을 지운다`() {
        val old = file("1000000022.jpg", 286_186, TimeUnit.HOURS.toMillis(2))

        val removed = CapturedFileStore.sweep(folder.root, now)

        assertEquals(1, removed)
        assertFalse(old.exists())
    }

    @Test
    fun `방금 고른 사진은 남긴다`() {
        // 압축이 불가능한 환경에서는 제출 시점까지 이 파일을 참조한다. 지우면 업로드가 깨진다.
        val fresh = file("1000000023.jpg", 443_856, TimeUnit.SECONDS.toMillis(30))

        val removed = CapturedFileStore.sweep(folder.root, now)

        assertEquals(0, removed)
        assertTrue(fresh.exists())
    }

    @Test
    fun `유예를 넘긴 빈 촬영 파일을 지운다`() {
        // 선택기를 열 때마다 하나씩 생긴다. 촬영을 취소하면 0바이트인 채로 남는다.
        val abandoned = file("Capture_500954307159802784.jpg", 0, TimeUnit.MINUTES.toMillis(5))

        val removed = CapturedFileStore.sweep(folder.root, now)

        assertEquals(1, removed)
        assertFalse(abandoned.exists())
    }

    @Test
    fun `촬영 중일 수 있는 빈 파일은 유예 안에서는 남긴다`() {
        // 카메라 Intent 는 빈 파일을 먼저 만들고 그 자리에 사진을 쓴다.
        val inFlight = file("Capture_6255571286228407395.jpg", 0, TimeUnit.SECONDS.toMillis(10))

        val removed = CapturedFileStore.sweep(folder.root, now)

        assertEquals(0, removed)
        assertTrue(inFlight.exists())
    }

    @Test
    fun `빈 파일은 사진보다 먼저 정리된다`() {
        // 같은 나이(10분)라도 빈 파일만 지워져야 한다. 임계값이 하나로 합쳐지면 이 테스트가 깨진다.
        val ten = TimeUnit.MINUTES.toMillis(10)
        val empty = file("Capture_1.jpg", 0, ten)
        val photo = file("1000000024.jpg", 1_024, ten)

        val removed = CapturedFileStore.sweep(folder.root, now)

        assertEquals(1, removed)
        assertFalse(empty.exists())
        assertTrue(photo.exists())
    }

    @Test
    fun `하위 디렉터리는 건드리지 않는다`() {
        val nested = folder.newFolder("subdir")
        assertTrue(nested.setLastModified(now - TimeUnit.DAYS.toMillis(30)))

        val removed = CapturedFileStore.sweep(folder.root, now)

        assertEquals(0, removed)
        assertTrue(nested.exists())
    }

    @Test
    fun `디렉터리가 아직 없으면 조용히 넘어간다`() {
        val missing = File(folder.root, "never-created")

        assertEquals(0, CapturedFileStore.sweep(missing, now))
    }

    @Test
    fun `보관 기간 경계에서는 지운다`() {
        val exactly = file("1000000025.jpg", 512, CapturedFileStore.PHOTO_RETENTION_MILLIS)

        assertEquals(1, CapturedFileStore.sweep(folder.root, now))
        assertFalse(exactly.exists())
    }
}
