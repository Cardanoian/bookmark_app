package net.chaekgalpi.app

import net.chaekgalpi.app.web.FileChooserCallbackGuard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * WebView 파일 선택 콜백 감시자 검증.
 *
 * 여기서 지키는 계약이 깨지면 증상이 조용하지 않다 — 두 번 응답하면 Chromium 이 프로세스를 죽이고,
 * 응답하지 않으면 사진 선택 버튼이 영영 먹통이 된다.
 */
class FileChooserCallbackGuardTest {

    /** 테스트용 가짜 스레드 환경. 메인 스레드 여부를 직접 조종한다. */
    private class Env(var onMainThread: Boolean = true) {
        val posted = mutableListOf<() -> Unit>()
        val received = mutableListOf<Any?>()
        var deliveredOnMainThread = mutableListOf<Boolean>()

        fun <T> guard(): FileChooserCallbackGuard<T> = FileChooserCallbackGuard(
            isMainThread = { onMainThread },
            postToMainThread = { posted += it },
            deliver = { value ->
                received += value
                deliveredOnMainThread += onMainThread
            }
        )

        /** 메인 큐에 쌓인 작업을 메인 스레드로서 실행한다. */
        fun drainMainQueue() {
            val queued = posted.toList()
            posted.clear()
            val previous = onMainThread
            onMainThread = true
            queued.forEach { it() }
            onMainThread = previous
        }
    }

    @Test
    fun `메인 스레드에서 받은 결과는 곧바로 전달한다`() {
        val env = Env(onMainThread = true)
        val guard = env.guard<Array<String>>()
        val result = arrayOf("content://picked")

        guard.receive(result)

        assertEquals(1, env.received.size)
        assertSame(result, env.received.single())
        assertTrue("메인 스레드였으므로 post 를 거치지 않아야 한다", env.posted.isEmpty())
    }

    @Test
    fun `IO 스레드에서 받은 결과는 메인 스레드로 넘겨 전달한다`() {
        // core 1_3_1 이 실제로 이렇게 부른다 - BrowseFilesDelegate 의 코루틴 컨텍스트가 IO 디스패처다.
        val env = Env(onMainThread = false)
        val guard = env.guard<Array<String>>()

        guard.receive(arrayOf("content://picked"))

        assertTrue("아직 전달되면 안 된다", env.received.isEmpty())
        assertEquals(1, env.posted.size)

        env.drainMainQueue()

        assertEquals(1, env.received.size)
        assertEquals(listOf(true), env.deliveredOnMainThread)
    }

    @Test
    fun `취소는 null 로 정확히 한 번 전달된다`() {
        val env = Env(onMainThread = true)
        val guard = env.guard<Array<String>>()

        guard.receive(null)
        guard.receive(null)

        assertEquals(1, env.received.size)
        assertNull(env.received.single())
    }

    @Test
    fun `결과가 온 뒤 취소가 또 와도 무시한다`() {
        val env = Env(onMainThread = true)
        val guard = env.guard<Array<String>>()
        val result = arrayOf("content://picked")

        guard.receive(result)
        guard.receive(null)

        assertEquals(1, env.received.size)
        assertSame(result, env.received.single())
    }

    @Test
    fun `응답 전에는 pending 이고 응답하면 아니다`() {
        val env = Env(onMainThread = true)
        val guard = env.guard<Array<String>>()

        assertTrue(guard.isPending)
        guard.receive(null)
        assertFalse(guard.isPending)
    }

    @Test
    fun `IO 스레드 전달이 예약된 순간부터 pending 이 아니다`() {
        // 예약만 되고 아직 실행 전이어도 "이미 응답한 것"으로 봐야 한다.
        // 그래야 그 사이에 새 요청이 와도 같은 콜백에 두 번 응답하지 않는다.
        val env = Env(onMainThread = false)
        val guard = env.guard<Array<String>>()

        guard.receive(arrayOf("content://picked"))

        assertFalse(guard.isPending)
    }

    @Test
    fun `여러 스레드가 동시에 응답해도 한 번만 전달된다`() {
        val delivered = AtomicInteger(0)
        val guard = FileChooserCallbackGuard<Array<String>>(
            isMainThread = { true },
            postToMainThread = { it() },
            deliver = { delivered.incrementAndGet() }
        )

        val threads = 16
        val start = CountDownLatch(1)
        val done = CountDownLatch(threads)
        repeat(threads) {
            Thread {
                start.await()
                guard.receive(arrayOf("content://picked"))
                done.countDown()
            }.start()
        }
        start.countDown()
        assertTrue(done.await(5, TimeUnit.SECONDS))

        assertEquals(1, delivered.get())
    }
}
