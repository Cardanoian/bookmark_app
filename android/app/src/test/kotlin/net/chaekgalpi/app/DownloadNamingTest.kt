package net.chaekgalpi.app

import net.chaekgalpi.app.downloads.DownloadNaming
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 저장 파일명 정규화 검증.
 *
 * 실제 서버 응답을 기준으로 삼는다 — Rails `send_data ... filename: "reports_5axis_2026-08-29.csv",
 * disposition: "attachment"` 는 `filename` 과 `filename*` 을 함께 보낸다.
 */
class DownloadNamingTest {

    // ---- 정상 경로 ----

    @Test fun `따옴표 파일명을 그대로 쓴다`() {
        assertEquals(
            "reports_5axis_2026-08-29.csv",
            DownloadNaming.fileName(
                """attachment; filename="reports_5axis_2026-08-29.csv"""",
                "https://chaekgalpi.net/teacher/exports.csv",
                "text/csv"
            )
        )
    }

    @Test fun `filename 별표를 우선해 한글 파일명을 복원한다`() {
        // filename 은 ASCII 로 뭉개져 오고 filename* 에만 원래 이름이 담긴다.
        val header = "attachment; filename=\"____.csv\"; " +
            "filename*=UTF-8''%ED%95%99%EC%83%9D%EB%AA%A9%EB%A1%9D.csv"

        assertEquals("학생목록.csv", DownloadNaming.fileName(header, null, "text/csv"))
    }

    @Test fun `따옴표 없는 토큰 파일명도 읽는다`() {
        assertEquals(
            "stats.csv",
            DownloadNaming.fileName("attachment; filename=stats.csv", null, "text/csv")
        )
    }

    @Test fun `헤더가 없으면 URL 마지막 조각을 쓴다`() {
        assertEquals(
            "agree.pdf",
            DownloadNaming.fileName(null, "https://chaekgalpi.net/agree.pdf", "application/pdf")
        )
    }

    @Test fun `URL 조각의 퍼센트 인코딩을 푼다`() {
        assertEquals(
            "동의서.pdf",
            DownloadNaming.fileName(null, "https://chaekgalpi.net/%EB%8F%99%EC%9D%98%EC%84%9C.pdf", null)
        )
    }

    // ---- 경로 문자·제어문자 ----

    @Test fun `경로 조각을 버린다`() {
        assertEquals(
            "passwd",
            DownloadNaming.fileName("""attachment; filename="../../etc/passwd"""", null, null)
        )
        assertEquals(
            "b.csv",
            DownloadNaming.fileName("""attachment; filename="a\b.csv"""", null, "text/csv")
        )
    }

    @Test fun `점만 있는 이름은 폴백으로 떨어진다`() {
        assertEquals("download", DownloadNaming.fileName("""attachment; filename=".."""", null, null))
        assertEquals("download", DownloadNaming.fileName("""attachment; filename="."""", null, null))
    }

    @Test fun `제어문자를 밑줄로 바꾼다`() {
        val name = DownloadNaming.fileName(
            "attachment; filename=\"report\nname.csv\"",
            null,
            "text/csv"
        )
        assertEquals("report_name.csv", name)
        assertFalse(name.contains('\n'))
    }

    @Test fun `파일 관리자가 싫어하는 문자를 밑줄로 바꾼다`() {
        assertEquals(
            "a_b_c.csv",
            DownloadNaming.fileName("""attachment; filename="a:b|c.csv"""", null, "text/csv")
        )
    }

    // ---- 길이 ----

    @Test fun `긴 이름은 확장자를 살리며 자른다`() {
        val long = "가".repeat(300) + ".csv"
        val name = DownloadNaming.fileName("""attachment; filename="$long"""", null, "text/csv")

        assertTrue("100자 이하여야 한다: ${name.length}", name.length <= 100)
        assertTrue("확장자가 살아 있어야 한다", name.endsWith(".csv"))
    }

    // ---- 확장자 보완 ----

    @Test fun `확장자가 없으면 MIME 으로 보완한다`() {
        assertEquals(
            "exports.csv",
            DownloadNaming.fileName("""attachment; filename="exports"""", null, "text/csv; charset=utf-8")
        )
    }

    // 교사 원자료 내보내기는 CSV 에서 XLSX 로 바뀌었다. 라우팅으로 잡은 다운로드는 응답 헤더가
    // 없어 URL 마지막 조각(`reports_xlsx`)밖에 없으므로, MIME 보완이 없으면 확장자 없이 저장된다.
    @Test fun `엑셀 MIME 이면 xlsx 를 붙인다`() {
        assertEquals(
            "reports_xlsx.xlsx",
            DownloadNaming.fileName(
                null,
                "https://chaekgalpi.net/teacher/exports/reports_xlsx",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            )
        )
    }

    @Test fun `확장자가 있으면 서버가 준 것을 존중한다`() {
        assertEquals(
            "exports.txt",
            DownloadNaming.fileName("""attachment; filename="exports.txt"""", null, "text/csv")
        )
    }

    @Test fun `모르는 MIME 이면 확장자를 붙이지 않는다`() {
        assertEquals(
            "blob",
            DownloadNaming.fileName("""attachment; filename="blob"""", null, "application/x-unknown")
        )
    }

    // ---- 폴백 ----

    @Test fun `아무 단서가 없으면 download 다`() {
        assertEquals("download", DownloadNaming.fileName(null, null, null))
        assertEquals("download", DownloadNaming.fileName("attachment", null, null))
        assertEquals("download", DownloadNaming.fileName(null, "https://chaekgalpi.net/", null))
    }

    @Test fun `깨진 퍼센트 인코딩은 다음 후보로 넘어간다`() {
        // filename* 디코딩이 실패해도 예외를 던지지 않고 URL 폴백까지 내려가야 한다.
        val header = "attachment; filename*=UTF-8''%ZZ"
        assertEquals("stats.csv", DownloadNaming.fileName(header, "https://chaekgalpi.net/stats.csv", null))
    }
}
