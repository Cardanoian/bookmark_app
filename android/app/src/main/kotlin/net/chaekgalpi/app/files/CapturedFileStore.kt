package net.chaekgalpi.app.files

import android.content.Context
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * 사진 선택·촬영이 앱 저장소에 남기는 파일을 나이 기준으로 정리한다.
 *
 * ### 왜 필요한가 (에뮬레이터 실측)
 * Hotwire core 의 `HotwireFileProvider` 는 **캐시가 아니라 `filesDir/shared`** 를 쓴다.
 * 즉 OS 가 알아서 비워 주지 않는다. 그리고 core 가 청소하는 시점은
 * `Session` 생성자에서 부르는 `FileChooserDelegate.deleteCachedFiles()` **한 번뿐**이라,
 * 앱을 계속 켜 두는 동안에는 계속 쌓인다. 실제로 한 세션 안에서 이런 상태를 확인했다.
 *
 * ```
 * files/shared/1000000022.jpg                 286,186  ← 학생이 고른 손글씨 독후감 원본 사본
 * files/shared/Capture_3715765213336118774.jpg      0  ← 선택기를 열 때마다 생기는 빈 촬영 파일
 * files/shared/Capture_500954307159802784.jpg       0
 * files/shared/Capture_6255571286228407395.jpg      0
 * ```
 *
 * 빈 파일은 그냥 쓰레기지만, **고른 사진은 초등학생 손글씨 원본**이다. 업로드가 끝난 뒤에도
 * 앱 저장소에 남아 있을 이유가 없다.
 *
 * ### 왜 즉시 지우지 않는가
 * 콜백 직후에 지우면 안 된다 — WebView 가 `content://` URI 로 **비동기로** 읽고,
 * 압축이 불가능한 환경에서는 제출 시점까지 원본 파일을 참조한다. 그래서 나이로만 판단한다.
 * [PHOTO_RETENTION_MILLIS] 를 넘긴 파일은 어떤 진행 중인 업로드에도 속할 수 없다.
 */
object CapturedFileStore {

    /**
     * `HotwireFileProvider` 가 쓰는 디렉터리 이름. core 내부 상수라 공개 API 가 없어
     * 실측(`files/shared`)으로 확인한 값을 둔다. core 버전을 올리면 이 경로가 그대로인지 확인한다.
     */
    private const val DIRECTORY_NAME = "shared"

    /** 사진 보관 상한. OCR 업로드는 몇 초면 끝나므로 1시간이면 진행 중인 작업과 겹치지 않는다. */
    val PHOTO_RETENTION_MILLIS: Long = TimeUnit.HOURS.toMillis(1)

    /**
     * 빈 촬영 파일의 유예. 카메라 Intent 는 빈 파일을 **먼저 만들고** 그 자리에 사진을 쓴다.
     * 촬영이 진행 중인 파일을 지우지 않도록 잠깐 기다린다.
     */
    val EMPTY_FILE_GRACE_MILLIS: Long = TimeUnit.MINUTES.toMillis(1)

    fun directory(context: Context): File = File(context.filesDir, DIRECTORY_NAME)

    /**
     * [directory] 안을 훑어 오래된 것을 지운다. 지운 개수를 돌려준다.
     *
     * 파일 이름·경로를 로그로 남기지 않는다(아동 PII). 하위 디렉터리는 건드리지 않는다 —
     * core 가 만드는 구조가 아니고, 모르는 디렉터리를 지우는 쪽이 더 위험하다.
     */
    fun sweep(
        directory: File,
        now: Long,
        photoRetentionMillis: Long = PHOTO_RETENTION_MILLIS,
        emptyFileGraceMillis: Long = EMPTY_FILE_GRACE_MILLIS
    ): Int {
        val entries = directory.listFiles() ?: return 0
        var removed = 0
        for (entry in entries) {
            if (!entry.isFile) continue
            val age = now - entry.lastModified()
            val threshold = if (entry.length() == 0L) emptyFileGraceMillis else photoRetentionMillis
            if (age >= threshold && entry.delete()) removed++
        }
        return removed
    }
}
