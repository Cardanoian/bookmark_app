# 연구용 비식별 원자료 추출(시드 아님, 읽기 전용). 2026-09-16 에 걷어낸 교사 화면의 5축 원자료
# 내보내기(`teacher/exports#reports_xlsx`)를 **상시 표면 없이** 대신한다 — 아이 글의 점수표를 누구나
# 언제든 내려받을 수 있는 경로는 제품에 두지 않고, 연구자가 필요할 때 한 번 돌려 파일을 만든다.
#
#   research:reports_5axis            — 초안(사전)·고쳐쓰기(사후) 5축 비교 CSV + 산출 메타 기록
#
# 범위는 환경변수로 좁힌다(없으면 전체):
#   CLASSROOM_IDS=1,2   특정 학급만          SCHOOL_ID=3   한 학교만
#   OUT_DIR=tmp/…       산출 위치(기본 tmp/research_export — tmp/ 는 git 밖이다)
#
# ⚠️ 산출 파일은 가명 처리를 했어도 **다른 자료와 합치면 학생을 알아볼 수 있다**. 저장소에 커밋하지
# 말고(기본 산출 위치가 tmp/ 인 이유다), 학교가 승인한 환경에서만 다루고, 분석이 끝나면 지운다.
namespace :research do
  desc "초안·고쳐쓰기 5축 비교 비식별 원자료 CSV 추출(읽기 전용, 산출 메타 기록 동봉)"
  task reports_5axis: :environment do
    require "csv"

    # 가명 ID 의 목적 문자열은 걷어낸 화면이 쓰던 것을 그대로 둔다 — 이미 배포된 파일과 같은 학생이
    # 같은 ID 로 이어져야 예전 산출물과 대조할 수 있다(목적 문자열이 바뀌면 전부 달라진다).
    pseudonym_purpose = "teacher-reports-xlsx-v1"
    pseudonym_key = Rails.application.key_generator.generate_key(pseudonym_purpose, 32)
    pseudonym_for = lambda do |school_id, user_id|
      digest = OpenSSL::HMAC.hexdigest("SHA256", pseudonym_key, "school:#{school_id}:user:#{user_id}")
      "학생-#{digest.first(12).upcase}"
    end

    scope = Report.where(revision_of_id: nil).includes(:user, :book, :revisions)
    if ENV["CLASSROOM_IDS"].present?
      classroom_ids = ENV["CLASSROOM_IDS"].split(",").map { |id| id.strip.to_i }.reject(&:zero?)
      scope = scope.where(classroom_id: classroom_ids)
    end
    if ENV["SCHOOL_ID"].present?
      scope = scope.where(classroom_id: Classroom.where(school_id: ENV["SCHOOL_ID"].to_i).select(:id))
    end

    candidates = scope.order(:user_id, :created_at).to_a
    # 미제출 초안은 뺀다. "학생이 낸 글"이 아니라 쓰다 만 글이라, 섞으면 사전 점수가 없는 행이
    # 결측처럼 보이고 학급 평균이 내려앉는다(걷어낸 화면은 이 경계가 없었다 — 베타 피드백 6번).
    reports = candidates.select { |report| report.submitted_at.present? }
    skipped_drafts = candidates.size - reports.size

    axes = ReadingDomain::RUBRIC_AXES
    headers = [
      "학생 가명 ID", "도서",
      "사전_평균", "사전_등급",
      *axes.map { |axis| "사전_#{ReadingDomain::AXIS_LABELS[axis]}" },
      "사후_평균", "사후_등급",
      *axes.map { |axis| "사후_#{ReadingDomain::AXIS_LABELS[axis]}" },
      "향상도"
    ]

    # 표 계산에 쓰는 값이 스프레드시트에서 수식이 되지 않게 한다. 책 제목은 학생 자유 입력이라
    # `=HYPERLINK(...)` 같은 값이 들어올 수 있다(CSV 는 셀 타입이 없어 여는 순간 수식이 된다).
    sanitize = lambda do |value|
      text = value.to_s
      text.match?(/\A[=+\-@\t\r]/) ? "'#{text}" : text
    end

    students = {}
    rows = reports.map do |report|
      revision = report.revisions.select { |candidate| candidate.submitted_at.present? }.max_by(&:created_at)
      pre = report.rubric_scores
      post = revision&.rubric_scores || {}
      pseudonym = students[report.user_id] ||= pseudonym_for.call(report.user&.school_id, report.user_id)
      [
        pseudonym,
        sanitize.call(report.book&.title.presence || report.book_title),
        report.avg, report.level,
        *axes.map { |axis| pre[axis] },
        revision&.avg, revision&.level,
        *axes.map { |axis| post[axis] },
        revision&.improvement
      ]
    end

    paired = rows.count { |row| row[headers.index("사후_평균")].present? }
    out_dir = Rails.root.join(ENV["OUT_DIR"].presence || "tmp/research_export")
    FileUtils.mkdir_p(out_dir)
    stamp = Time.current.strftime("%Y%m%d_%H%M%S")
    csv_path = out_dir.join("reports_5axis_#{stamp}.csv")
    meta_path = out_dir.join("reports_5axis_#{stamp}_산출메타.md")

    # 엑셀이 한글을 깨뜨리지 않게 BOM 을 붙인다(CSV 에는 인코딩 선언이 없다).
    File.write(csv_path, "﻿" + CSV.generate { |csv| csv << headers; rows.each { |row| csv << row } })

    revision = begin
      `git rev-parse --short HEAD`.strip.presence
    rescue StandardError
      nil
    end
    File.write(meta_path, <<~META)
      # 5축 원자료 산출 메타 (#{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')})

      | 항목 | 값 |
      |---|---|
      | 산출 파일 | `#{csv_path.basename}` |
      | 대상 범위 | #{ENV['CLASSROOM_IDS'].presence ? "학급 #{ENV['CLASSROOM_IDS']}" : (ENV['SCHOOL_ID'].presence ? "학교 #{ENV['SCHOOL_ID']}" : '전체')} |
      | 행 수(제출된 원본 글) | #{rows.size} |
      | 학생 수 | #{students.size} |
      | 사후(고쳐쓰기)까지 있는 짝 | #{paired} |
      | 제외한 미제출 초안 | #{skipped_drafts} |
      | 실행 환경 | Ruby #{RUBY_VERSION} · Rails #{Rails.version} · #{Rails.env} |
      | 코드 판본 | #{revision || '(git 정보 없음)'} |

      ## 포함·제외 기준
      - **행 = 제출된 원본 독후감 1편**(`revision_of_id` 없음 + `submitted_at` 있음). 고쳐쓰기 글은 같은 행의 '사후' 열로 들어간다.
      - 미제출 초안은 제외했다(위 표의 '제외한 미제출 초안').
      - 사후 열은 **제출된 고쳐쓰기 중 가장 최근 것**이다. 고쳐쓰기가 없으면 사후·향상도 열이 빈다.

      ## 열 뜻
      - `학생 가명 ID` — 서버 비밀키 HMAC(`school:<학교>:user:<학생>`)의 앞 12자리. 대응표는 어디에도 없고, 같은 학생은 산출물마다 같은 ID 를 받는다.
      - `도서` — 학생이 고르거나 적은 책 제목. **자유 입력이라 드문 제목은 그 자체가 식별 단서가 될 수 있다.**
      - `사전_*` / `사후_*` — 5축(#{axes.map { |axis| ReadingDomain::AXIS_LABELS[axis] }.join('·')}) 점수와 평균·등급.
      - `향상도` — 고쳐쓰기 글의 `improvement`(사후 평균 − 직전 평균).

      ## 읽을 때 주의
      - 점수는 **AI 첨삭 값**이다. 교사가 조정한 축(`teacher_rubric`)은 반영돼 있지 않아, 승인 화면에서 본 최종 점수와 다를 수 있다.
      - 가명 처리를 했어도 다른 자료와 합치면 학생을 알아볼 수 있다. 저장소에 커밋하지 말고, 분석이 끝나면 지운다.
    META

    puts "== 5축 원자료 추출 =="
    puts "행 #{rows.size} · 학생 #{students.size} · 사후까지 있는 짝 #{paired} · 제외한 미제출 초안 #{skipped_drafts}"
    puts "CSV : #{csv_path}"
    puts "메타: #{meta_path}"
    puts "⚠️ 산출 파일은 커밋하지 말고 승인된 환경에서만 다루세요."
  end
end
