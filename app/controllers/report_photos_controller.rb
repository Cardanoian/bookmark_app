# OCR 손글씨 사진(아동 PII)의 바이트를 Pundit 경계 안에서만 서빙하는 인증 프록시.
# Active Storage 기본 서명 URL 은 세션 없이도 접근 가능한 무인가 바이트 표면이라, 이 앱의
# `verify_authorized` fail-closed 철학과 맞지 않아 도입하지 않는다(docs/ocr_photo_display_plan.md §2.0).
#
# 인가 기준은 `ReportPolicy#show?` 다 — 페이지 인가를 그대로 미러해 학생 본인·담임 교사·
# 동일 학교 사서/교무가 자기 화면에서 보는 사진을 바이트 요청에서도 동일하게 볼 수 있게 한다
# (`review?` 로 좁히면 학생 본인이 자기 사진을 못 본다).
class ReportPhotosController < ApplicationController
  # 표시용 512px, 확대용 1600px. 원본(무제한) 바이트는 어떤 경로로도 서빙하지 않는다 —
  # `Blob#download` 가 blob 전체를 메모리에 올리므로 10MB 원본 동시 요청은 워커 메모리 스파이크가 된다.
  DISPLAY_LIMIT = [ 512, 512 ].freeze
  ZOOM_LIMIT = [ 1600, 1600 ].freeze

  def show
    report = Report.find(params[:id])   # RecordNotFound → 404 전파(삼키지 않음)
    authorize report, :show?            # NotAuthorizedError → 403 전파(아래 rescue 밖)
    photo = report.display_photo
    head :not_found and return unless photo

    # 반복 요청은 조건부 GET(304)으로 끊어 Puma 워커가 매번 variant 를 다운로드·전송하지 않게 한다.
    fresh_when(photo.blob, public: false)
    return if performed?

    send_variant(report, photo)
  end

  # 사진을 감싼 HTML 화면. **바이트는 여기서 서빙하지 않는다** — 뷰의 `<img>` 가 다시 [show] 를
  # 부르므로 인가 경계도 캐시 정책도 한 곳에 그대로 남는다.
  #
  # 앱(WebView)에서 확대 링크가 죽어 있어 만든 화면이다(계획 §N.5). 웹은 지금까지처럼 이미지
  # 바이트를 새 탭으로 열므로 이 액션을 지나지 않는다 — 다만 URL 로 직접 오면 웹에서도 정상 동작한다.
  def zoom
    @report = Report.find(params[:id])
    authorize @report, :show?
    head :not_found and return unless @report.display_photo
  end

  private

  # variant 처리 실패에만 국한한 rescue — 조회(`find`)·인가(`authorize`)는 이미 위에서 통과했으므로
  # 이 폴백은 인가를 우회할 수 없다(비인가 요청은 여기 도달 자체를 못 하고 403 으로 전파된다).
  #
  # **`LoadError` 를 함께 잡는 이유**: libvips 미설치 환경에서 `.processed` 는 ruby-vips 로딩 시점의
  # `LoadError`(< ScriptError)를 던진다 — `StandardError` 가 아니라 `rescue => e` 로는 안 잡혀 500 이 된다.
  # 사진 표시는 부가 기능이고 원본 폴백이 항상 가능하므로, 처리 계층 부재도 무중단 degrade 로 흡수한다.
  def send_variant(report, photo)
    served = photo.variant(resize_to_limit: variant_limit).processed
    send_data served.download, type: served.content_type, disposition: "inline"
  rescue StandardError, LoadError => e
    # PII 보호: URL·바이트는 남기지 않고 report id 와 예외 클래스만 기록한다.
    Rails.logger.warn("report photo variant failed for report #{report.id}: #{e.class}")
    send_data photo.download, type: photo.content_type, disposition: "inline"
  end

  def variant_limit
    params[:size] == "original" ? ZOOM_LIMIT : DISPLAY_LIMIT
  end
end
