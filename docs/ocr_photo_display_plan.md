# OCR 독후감 사진 512 표시 — 구현 계획 (ADR 포함)

> **상태: `implemented`(2026-07-27)** — ralplan 합의 플래닝(Planner·Architect·Critic 3자, 재리뷰 3회차) Critic **APPROVE** 후 **Option B(인증 프록시) 채택으로 구현 완료**. 구현 산출물·계획 대비 편차는 §8 참고.
>
> **결정된 사용자 결정 지점**: 아동 손글씨(P1-1 PII) 바이트 서빙 인가 모델은 문서 추천안인 **Option B(인증 프록시 컨트롤러) + A 이점 흡수**로 확정했다(§2.0·ADR). Option A(서명 URL obscurity)는 기각된 대안으로만 남는다.

작성 근거: 3자 합의 로그(2026-07-27). 대상 요구 원문 — "학생이 OCR로 독후감을 입력했을 때, 독후감 이미지는 현재 저장하지 않는데, 이제 512x512로 저장하고, 교사는 검토할 때 이미지를 같이 보면서 검토하도록 하는건 어떨까? 학생도 이미지 ocr을 했으면 해당 독후감을 볼 때는 이미지를 같이 보는거야."

---

## 0. 컨텍스트 · 전제 정정

사용자 요구 원문 "이미지를 현재 저장하지 않는다"는 **사실이 아니다**. `app/controllers/ocr_controller.rb:52`가 `@report.photo.attach(...)`로 사진을 Active Storage Disk에 **이미 영구 저장**하며 purge 로직이 없다. 따라서 실질 산출물:

1. **저장은 신규 작업이 아님** (이미 저장됨).
2. **표시(display)가 실제 작업** — 교사 검토 + 학생 상세에 OCR 사진 노출.
3. **"512"의 해석** — 저장 정책이 아니라 **표시용 512 축소 variant**(원본 훼손 금지).
4. **진짜 저장 이슈는 retention** — 원본이 무기한 보관된다. "512로 저장"의 동기가 저장 절감이라면 옳은 레버는 **retention/purge 정책**(§5, 범위 밖 후속).

**합의로 확정된 사실(gem 소스·앱 코드 대조 검증 완료)**
- `image_processing 1.14` + `ruby-vips 2.3` 존재, libvips는 `Dockerfile`(base+build)·`Dockerfile.dev` 모두 설치됨 → variant 생성 가능.
- Active Storage 전 환경 `Disk`(local), `active_storage_variant_records` 테이블 존재 → **마이그레이션 불필요**.
- `config/application.rb`가 `load_defaults 8.1` → variant_processor `:vips`, `track_variants: true`.
- CSP `img_src :self`가 동일 출처 variant 경로를 커버 → **CSP 변경 불필요**.
- `app/views/reports/_report_detail.html.erb`는 `Report#broadcast_detail_refresh`가 **request 없이** 렌더한다(AiReviewJob·교사 승인 방송) → 이 파티셜에는 뷰어·host 의존 로직을 넣지 않는다.
- `ReportPolicy#show?`는 학생 본인 + 담임 교사(`teacher_of_classroom?`) + **동일 학교 사서·교무(`same_school?`)** 를 허용한다. `review?`는 학생·사서·교무를 403시키므로 **바이트 프록시 게이트로는 `show?`가 유일한 정답**(review?로 바꾸면 학생 본인·동일학교 스태프가 자기 화면에서 사진을 못 봄).
- `reports_controller.rb#revise`는 새 revision을 `Current.user.reports.new(classroom: @report.classroom, input_mode: @report.input_mode, revision_of: @report)`로 만든다 → revision은 부모와 **동일 학생·동일 학급**이고 `input_mode`를 복사(revision도 `ocr?`)하나 **photo는 미승계**.
- `revision_of`는 mass-assign 불가(`report_params` 미포함)이고 revise만 더 오래된 부모를 가리키므로 id 단조감소 → **사이클 무한루프 불가**(단 hot path 방어로 depth cap 권장).
- 설정 semantics(gem `activestorage-8.1.3` 소스): `active_storage.urls_expire_in` = **페이지 임베드 링크(signed_blob_id) 만료**(기본 nil), `active_storage.service_urls_expire_in` = **최종 Disk 홉 만료**(기본 5분).

---

## 1. 설계 요약 (RALPLAN-DR, deliberate 모드)

### 1.1 원칙 (Principles)
1. **PII 최소 노출 표면**: 손글씨는 P1-1 PII. 기존 인가 경계 안에서만 표시하고, 목록 썸네일·인덱스 노출을 만들지 않는다. 바이트 서빙 인가는 명시적 설계 결정으로 승격한다.
2. **fail-closed 인가 정합**: 이 앱은 `verify_authorized` 안전망 기반이다. 사진 바이트 서빙도 `authorize` 게이트를 실제로 통과해야 하며, **인가 예외를 rescue로 삼키지 않는다**.
3. **방송 안전성 불변식 보존**: `_report_detail`은 request 없는 방송에서도 렌더된다 → 방송 파티셜 표면을 최소화하고, 불변 자원(사진)은 라이브 교체 영역이 아닌 show 스캐폴드(HTTP 뷰)에 둔다.
4. **OCR 인식률 우선**: 저장 원본을 훼손하지 않는다(비동기 OcrJob 이전에 다운스케일 개입 금지). 512는 표시용 variant.
5. **가용·안전 우선의 최소 변경**: 마이그레이션 없음. 뷰는 URL 문자열만 다뤄 렌더타임 크래시 표면을 제거하고, 처리 실패는 원본 폴백으로 무중단.

### 1.2 결정 동인 (Decision Drivers)
1. **아동 PII 바이트 서빙 인가 모델** — fail-closed 정합 vs 구현 비용/성능 (최우선).
2. **회귀 0** — 방송(AiReviewJob/approval)·OCR 파이프라인·인식률 무영향.
3. **운영 단순성·가용성** — 단일 서버·SQLite·Disk. 지연 variant + 조건부 GET 캐시, 메모리 유계.

### 1.3 쟁점별 채택 옵션
| 쟁점 | 채택 | 기각 대안 및 사유 |
|------|------|------------------|
| A. 512 처리 | **원본 보존 + 표시용 variant** | 저장 자체 다운스케일(원본 폐기): OcrJob 비동기라 OCR 전 다운스케일 시 인식률 하락(고위험)·원본 소실·롤백 불가 |
| B. 리사이즈 모드 | **`resize_to_limit`**(비율 유지) | `resize_to_fill`(정사각 크롭): 세로 손글씨 상·하단 잘림 → 가독성 파괴 |
| C. 바이트 인가 ⚠️ | **Option B 인증 프록시**(추천) | Option A 서명 URL obscurity: 무인가 바이트 표면 신설 + 뷰 `.variant()` 렌더 크래시 표면 (대안으로 유지) |
| D. 표시 위치 | **D1 HTTP-only 뷰**(`_report_detail` 밖·미변경) | D2 `_report_detail`에 표시: 방송 파티셜 계약 복잡화 대비 이득 없음 |
| E. 목록 썸네일 | **범위 제외** | 새 PII 표면·N variant 비용·요구 범위 밖 |
| F. 생성 시점 | **지연 생성**(프록시 첫 요청 `.processed` + 조건부 GET 캐시) | OcrJob `.processed` 사전 생성: 잡 커플링·미조회 사진 낭비 |
| G. 고쳐쓰기 승계 | **root까지 체인 추적 승계** | 미승계: 고쳐쓰기 검토 시 교사 원문 대조 단절 |

> D1 근거(교정): "방송 시 host 부재 예외"가 아니다(`report_photo_path`는 path 헬퍼라 방송에서도 동작). 참 근거는 **① 방송 파티셜 표면 최소화, ② 불변 자원을 라이브 교체 영역이 아닌 show 스캐폴드에 배치**.

### 1.4 Pre-mortem (실패 시나리오 3개 + 완화)
1. **인가 우회 PII 유출** — rescue가 메서드 전체를 감싸면 `authorize`가 던지는 `Pundit::NotAuthorizedError`(< StandardError)를 rescue가 먼저 잡아 원본 바이트를 서빙(fail-open). `Report.find`의 `RecordNotFound`도 삼켜 500.
   → **완화**: rescue를 `authorize` **이후 variant 처리·서빙 구간에만** 국한하고 조회/인가 예외는 전파(403/404). 테스트에 "비인가 사용자 + variant 실패" 조합으로 폴백이 인가를 우회하지 않음(403 유지)을 단언. (`ApplicationController`의 `rescue_from Pundit::NotAuthorizedError → head :forbidden`이 전파를 403으로 처리함을 확인.)
2. **무인가 바이트 서빙 표면(Option A obscurity 의존)** — signed_id는 영구·추측 불가하나 무인가라 URL 유출 시 세션 없이 접근. Option A는 뷰 `.variant()` 렌더타임 `InvariableError` 크래시 표면도 있음.
   → **완화**: Option B로 요청마다 Pundit 강제(무인가 표면 미신설) + 뷰는 URL 문자열만 다뤄 렌더 크래시 불가. Option A 채택 시 무인가 표면·뷰 rescue 필요를 의식적으로 문서화·수용(AC A2).
3. **variant 처리 실패 / 메모리 스파이크 / vips 부재** — `.variant()`는 미처리 객체 생성뿐, 실제 vips 처리는 바이트 GET 시점(`.processed`). `Blob#download`는 blob 전체를 메모리 적재 → `size=original`(≤10MB) 동시 요청 시 워커 메모리 스파이크. resolver가 hot path라 렌더당 belongs_to 반복 쿼리.
   → **완화**: (a) 프록시 narrowed rescue → 원본 폴백, (b) `size=original`을 1600px 유계 variant로 캡(판독 충분 + 메모리·원본노출 동시 완화), (c) 512 경로 `fresh_when` 조건부 GET, (d) resolver depth cap(10) + memoize. libvips Docker 설치 확인됨.

### 1.5 PII 보호 논거 · 설정 semantics
**보호 근거(정확)**: (i) 추측 불가 HMAC signed_id, (ii) 페이지 렌더가 Pundit `show?`/`review?`로 게이트(비인가자에게 URL 미노출), (iii) URL·바이트 미로깅, (iv) 촬영 안내(`_photo_guide`의 식별정보 프레임 배제). **Option B 추가**: (v) 바이트 요청마다 Pundit 실제 강제 → (i) obscurity 의존 제거.

**설정 처리**:
- `active_storage.urls_expire_in` = 페이지 임베드 링크 만료. 짧게 설정하면 검토 화면을 그 시간 이상 열어둘 때 브라우저 재검증에서 `InvalidSignature` → `head :not_found` → **깨진 이미지 회귀**. 유출 URL 유효 창을 좁히는 한계적 이득은 있으나 UX 회귀에 압도됨 → **설정하지 않는다**.
- `active_storage.service_urls_expire_in` = 최종 Disk 홉 만료(기본 5분). 적정 → **손대지 않는다**.

---

## 2. 구현 계획

### 2.0 확정 설계 (Option B + A 이점 흡수)
Option B 채택 + A의 장점 흡수: (1) rescue를 처리 구간에만 국한, (2) `size=original`을 1600px 유계 variant로 캡, (3) 512 경로 `fresh_when` 캐싱, (4) 뷰는 URL 문자열만 두어 렌더 크래시 표면 제거. → B의 인가 정합 + A의 가용성·캐시·렌더 안전을 모두 취함.

| 기준 | Option A (서명 URL) | Option B (인증 프록시, 추천) |
|---|---|---|
| 바이트 인가 | 없음(HMAC obscurity) | Pundit `show?` 실제 강제 |
| fail-closed 정합 | 낮음(verify_authorized 밖) | 높음 |
| 뷰 렌더 안전 | `.variant()` `InvariableError` 크래시 표면 → 뷰 rescue 필요 | URL 문자열만 → 렌더 크래시 불가 |
| variant 실패 폴백 | 불가(브라우저 서브요청) → 깨진 썸네일 | 컨트롤러 `rescue → 원본` |
| 성능/메모리 | AS 직접 서빙(효율) | 워커 점유 — 1600 캡 + 조건부 GET로 완화 |
| PII 표면 | **무인가 바이트 서빙 표면 신설** | 신설 안 함 |

### 2.1 파일별 변경 목록
**신규(공통)**
- `app/views/reports/_ocr_photo.html.erb` — 공용 표시 파티셜(locals: `report`). HTTP 뷰 전용.

**신규(Option B)**
- `app/controllers/report_photos_controller.rb` — `#show`: 조회 → `authorize :show?` → 유계 variant `send_data`, narrowed rescue → 원본 폴백, `fresh_when` 캐시.
- `test/integration/report_photo_serving_test.rb`.

**수정(코드, 공통)**
- `app/models/report.rb` — `display_photo`(root 체인 + depth cap + memoize), `display_photo?`. 스키마·첨부 정의 무변경.
- `app/views/teacher/reviews/show.html.erb` — "학생이 쓴 글" 카드(22–24행) 근처에 `render "reports/ocr_photo", report: @report`.
- `app/views/reports/show.html.erb` — `render "reports/report_detail"`(7행) **밖**(page-actions 위)에 `render "reports/ocr_photo", report: @report`. `_report_detail` **미변경**.
- `config/routes.rb` — 명시 라우트: `get "reports/:id/photo", to: "report_photos#show", as: :report_photo`.

> **철회**: 이전 초안의 `config.active_storage.urls_expire_in = 5.minutes` 및 그에 딸린 `config/environments/*` 변경은 도입하지 않는다(§1.5).

**수정(문서 — CLAUDE.md 마트료시카 규칙)**
- `app/views/CLAUDE.md`(`reports/` 파티셜에 `_ocr_photo`·표시 지점) · `app/models/CLAUDE.md`(`display_photo`/`display_photo?`) · `app/controllers/CLAUDE.md`(`report_photos_controller`) · `config/CLAUDE.md`(`report_photo` 라우트) · `test/CLAUDE.md`(신규 테스트) · `docs/CLAUDE.md`(이 문서 인덱스 — 이미 반영).

### 2.2 단계 순서
1. 모델 resolver(root 체인·depth cap·memoize) → 2. 프록시 컨트롤러 + 명시 라우트 + narrowed rescue + 1600 캡 + fresh_when → 3. 공용 파티셜 → 4. 교사·학생 show 삽입 → 5. 테스트(§3) → 6. CLAUDE.md 갱신 → 7. 검증(§4).

### 2.3 예상 코드 스케치
```ruby
# app/models/report.rb (추가) — root 체인 + depth cap(사이클/코럽트 방어) + memoize(hot path 반복 쿼리 제거)
def display_photo
  return @display_photo if defined?(@display_photo)
  node = self
  10.times do
    break if node.nil? || node.photo.attached?
    node = node.revision_of
  end
  @display_photo = node&.photo&.attached? ? node.photo : nil
end

# revise 가 input_mode 를 복사하므로 revision 도 ocr? — 별도 revision_of&.ocr? 절 불필요.
def display_photo?
  ocr? && display_photo.present?
end
```

```ruby
# app/controllers/report_photos_controller.rb (신규)
# 인증 프록시: 사진 바이트를 Pundit 경계 안에서만 스트리밍(무인가 서명 URL 표면 미신설).
class ReportPhotosController < ApplicationController
  def show
    report = Report.find(params[:id])   # RecordNotFound → 404 전파(삼키지 않음)
    authorize report, :show?            # NotAuthorizedError → 403 전파(rescue 밖)
    photo = report.display_photo
    head :not_found and return unless photo

    fresh_when(photo.blob, public: false)  # 반복 요청 조건부 GET(304) — Puma 부하 완화
    return if performed?

    begin
      # size=original 도 1600px 유계 variant 로 캡 → 메모리 스파이크·원본 바이트 노출 동시 완화
      dimensions = params[:size] == "original" ? [ 1600, 1600 ] : [ 512, 512 ]
      served = photo.variant(resize_to_limit: dimensions).processed
      send_data served.download, type: served.content_type, disposition: "inline"
    rescue => e   # variant 처리 실패(vips 부재·손상)에만 국한 — 인가/조회는 이미 위에서 통과
      Rails.logger.warn("report photo variant failed for report #{report.id}: #{e.class}")
      send_data photo.download, type: photo.content_type, disposition: "inline"
    end
  end
end
```

```ruby
# config/routes.rb — 컨트롤러 #show · 헬퍼 report_photo_path · 파라미터 :id 정렬
get "reports/:id/photo", to: "report_photos#show", as: :report_photo
```

```erb
<%# app/views/reports/_ocr_photo.html.erb — 뷰는 URL 문자열만(렌더 크래시 표면 0) %>
<% if report.display_photo? %>
  <section class="card">
    <h2 class="mb-2 text-sm font-semibold text-steel">사진 원본</h2>
    <%= link_to report_photo_path(report, size: :original), target: "_blank", rel: "noopener" do %>
      <%= image_tag report_photo_path(report),
            alt: "학생이 촬영한 손글씨 독후감 사진",
            class: "max-w-full h-auto rounded-md border border-hairline-soft shadow-sm",
            loading: "lazy" %>
    <% end %>
    <p class="mt-1 text-xs text-stone">이미지를 누르면 더 크게 볼 수 있어요.</p>
  </section>
<% end %>
```

> **Option A 변형(대안, 채택 시)**: 컨트롤러/라우트 생략, 파티셜에서 `image_tag report.display_photo.variant(resize_to_limit: [512,512])` — **단 `.variant()` 렌더타임 `InvariableError` 대비 뷰 rescue 필요**, 확대는 `rails_blob_path`. 무인가 바이트 표면·렌더 크래시 트레이드오프 수반.

---

## 3. 확장 테스트 계획
- **Unit(모델)**: `display_photo` — 자기 / 부모 / **다세대 조상** / nil / **depth cap 장쇄** / memoize(반복 호출 1쿼리). `display_photo?`(`ocr?` AND 사진).
- **Integration(교사)**: `teacher/reviews/show` — OCR 렌더 / 비-OCR 미렌더 / 타 학급 담임 403(회귀).
- **Integration(학생)**: `reports/show` — 본인 OCR 렌더 + 확대 링크 / 비-OCR 미렌더 / 타 학생 차단 / **다세대 고쳐쓰기 root 사진 표시**.
- **바이트 서빙(Option B)**: 인가 매트릭스 — 본인 200 / 담임 200 / **동일 학교 사서·교무 200**(`show?`의 `same_school?` — 바이트 인가가 페이지 인가를 정확히 미러) / 타 학생·타 학급 교사 **403** / 비로그인 리다이렉트; `size=original` 1600 유계 스트리밍(원본 바이트 미노출); variant 실패 원본 폴백; **비인가 + variant 실패 조합 → 403 유지(폴백이 인가 우회 안 함)**; `RecordNotFound` → 404; `report_photo_path` 스모크(렌더 실패 없음); 512 경로 조건부 GET(304).
- **방송 회귀**: `ocr_job_test`·AiReviewJob·approval 방송·`report_photo_guide_test` 그린 + `_report_detail` OCR 리포트 request-less 렌더 무예외.
- **e2e/수동**: 실제 사진 OCR → 교사·학생 상세 512 표시 + 확대 → `docker compose up`(libvips) → **검토 화면 5분 이상 유지 후에도 이미지 정상 로드**(urls_expire_in 미설정 회귀 확인).
- **Observability**: variant 실패 시 `Rails.logger.warn`(report id·예외 클래스만, 바이트·URL 미로깅).

---

## 4. 검증 절차
```
bin/rails test test/models/report_test.rb \
  test/integration/report_photo_display_test.rb \
  test/integration/teacher_review_photo_test.rb \
  test/integration/report_photo_serving_test.rb \
  test/jobs/ocr_job_test.rb
bin/rails test            # 전체 회귀
bin/rubocop               # omakase
bin/brakeman -q           # 새 컨트롤러/send_data/라우트 정적 점검
```
- 수동 e2e: `docker compose up`(libvips) → 실제 사진 OCR → 교사·학생 512 표시 + 확대 → **검토 화면 5분 이상 유지 후 이미지 정상 로드 확인**.

---

## 5. 수용 기준 (Acceptance Criteria)

**공통**
1. **교사 표시**: 담임이 자기 학급 학생 OCR(`input_mode: ocr`) 검토 화면에서 512 사진 + 확대 링크를 본다.
2. **비-OCR 미표시**: keyboard/wongoji 검토·상세에 사진 섹션 미렌더.
3. **학생 표시**: 학생이 본인 OCR 상세에서 512 사진을 본다.
4. **인가 경계 무회귀(뷰)**: 타 학급 담임 검토 403, 타 학생 상세는 `ReportPolicy#show?`로 차단.
5. **방송 안전성**: `_report_detail` 방송 무예외·5축 첨삭 라이브 교체 정상(사진 미개입).
6. **OCR 인식률 무영향**: OcrJob 원본 blob OCR, 저장 원본 미축소. `ocr_job_test`·`ai/ocr_service_test` 그린.
7. **다세대 고쳐쓰기 승계**: OCR 독후감을 2회 이상 고쳐쓴 revision 상세에서 root 원본 사진 표시.
8. **스키마 불변**: `db/schema.rb` 변경(마이그레이션) 없이 동작.
9. **URL 만료 무회귀**: `urls_expire_in` 미설정, 검토/상세 화면 5분 이상 유지에도 이미지 미파손.
10. **문서 정합**: 변경 폴더 CLAUDE.md 갱신.

**Option B (추천)**
- **B1**: `report_photo_path`가 본인 200 / 담임 200 / **동일 학교 사서·교무 200**(`same_school?`) / 타 학생·타 학급 교사 **403** / 비로그인 리다이렉트를 반환한다. (바이트 인가 = 페이지 인가 미러)
- **B2**: `?size=original`이 1600px 유계 variant를 스트리밍하고(원본 바이트 미노출), variant 실패 시 원본 폴백으로 500 없음.
- **B3 (fail-closed 핵심)**: 비인가 요청은 variant가 실패할 상황에서도 rescue를 타지 않고 **403을 유지**한다(폴백이 인가를 우회하지 않음). `RecordNotFound`는 404로 전파.
- **B4**: 파티셜의 `report_photo_path(report)`/`(…, size: :original)`가 라우트·컨트롤러·`:id`와 정렬되어 렌더 실패(`undefined method`)가 없다.
- **B5**: 512 경로가 조건부 GET 헤더를 내보내 반복 요청에 304를 반환한다.

**Option A (대안)**
- **A1**: 사진 URL은 정책-스코프 뷰에서만 노출, 페이지 정상 렌더(뷰 rescue로 `InvariableError` 크래시 방지).
- **A2 (수용 위험 명시)**: 바이트 엔드포인트가 앱 세션 없이 서명 토큰만으로 접근 가능하고, variant 실패는 깨진 썸네일로 강등(페이지 정상)임을 테스트/문서로 의식적으로 기록.

---

## 6. ADR (Architecture Decision Record)

- **Decision**: OCR(`input_mode: ocr`) 독후감의 저장된 원본 사진을, 교사 검토 화면(`teacher/reviews/show`)과 학생 상세(`reports/show`)에 **표시용 512px `resize_to_limit` variant**로 노출한다. 바이트는 **인증 프록시 컨트롤러(`ReportPhotosController#show`, `authorize :show?`)**를 통해 Pundit 경계 안에서 서빙한다(Option B). 원본은 훼손하지 않고, 확대 링크는 1600px 유계 variant로 연다. 마이그레이션은 없다.
- **Drivers**: (1) 아동 PII(P1-1 손글씨) 바이트 서빙의 fail-closed 인가 정합, (2) 방송·OCR 파이프라인·인식률 회귀 0, (3) 단일 서버·SQLite·Disk 운영 단순성·가용성.
- **Alternatives considered**:
  - *바이트 인가*: **Option A(Rails 기본 서명 URL obscurity)** — 무인가 바이트 표면 신설 + 뷰 `.variant()` 렌더 크래시 표면. 대안으로 유지(사용자 결정 지점).
  - *512 처리*: 저장 자체를 512로 다운스케일(원본 폐기) — OCR 타이밍 리스크·롤백 불가로 기각.
  - *표시 위치*: `_report_detail`에 표시 — 방송 파티셜 계약 복잡화로 기각(D1 채택).
  - *URL 만료*: `urls_expire_in` 단축 — 5분+ 열람 시 깨진 이미지 회귀, 인가 이득 한계적이라 UX 회귀에 압도 → 도입 안 함.
- **Why chosen**: 이 앱의 `verify_authorized` fail-closed 철학 + 아동 PII 취급상, 앱 최초의 무인가 바이트 서빙 표면을 신설하지 않는 Option B가 정합적이다. rescue 스코프를 `authorize` 이후로 국한해 인가 예외가 전파(403)되도록 하고, 뷰는 URL 문자열만 다뤄 A의 렌더 크래시 표면을 제거하며, 1600 캡·조건부 GET으로 A의 가용성·캐시 이점을 흡수한다.
- **Consequences**:
  - (+) 바이트 접근이 페이지 인가와 동일 경계로 강제됨(과다·과소 노출 없음). 방송·OCR·스키마 무영향. 롤백 가능(원본 보존).
  - (−) 사진 바이트가 Puma 워커를 경유(캐싱 수동, 512는 조건부 GET로 완화). 원본 + variant 이중 저장. HEIC 등 비-variable 포맷 업로드 시 원본 폴백이 브라우저에서 미렌더 가능(클라 canvas 압축이 JPEG로 정규화하는지 확대 확인 권장).
- **Follow-ups**:
  - **retention/purge(범위 밖)**: 원본 무기한 보관이 진짜 PII 저장 이슈. 승인 후 N일 원본 purge(또는 원본 폐기·variant 보존) 정책은 별도 후속 과제. 채택은 사용자 몫.
  - 실행 시 확인: `_photo_capture`의 canvas 압축이 업로드를 JPEG로 정규화하는지, `size=original` 1600 variant의 동기 다운로드가 워커에 주는 부하.

---

## 7. 결정 완료 항목 (구현 시 확정)
1. **바이트 서빙 인가 모델**: **Option B(인증 프록시)** 확정 — Option A(서명 URL obscurity)는 기각.
2. **확대 링크 대상**: 1600px 유계 variant(`?size=original`) 확정(원본 blob 직노출 회피 + 판독 충분).
3. **목록 썸네일**: 범위 제외 확정.
4. **고쳐쓰기 승계**: root 체인 승계 확정.
5. **retention/purge 후속(범위 밖)**: §6 Follow-ups 참조 — 미착수.

---

## 8. 구현 기록 (2026-07-27)

**채택**: Option B(인증 프록시) + A 이점 흡수 — §2.0 그대로.

**산출물**
- 신규: `app/controllers/report_photos_controller.rb` · `app/views/reports/_ocr_photo.html.erb` · `test/integration/report_photo_serving_test.rb` · `test/integration/report_photo_display_test.rb` · `test/integration/teacher_review_photo_test.rb`
- 수정: `app/models/report.rb`(`display_photo`/`display_photo?`) · `config/routes.rb`(`report_photo`) · `app/views/reports/show.html.erb` · `app/views/teacher/reviews/show.html.erb` · `test/models/report_test.rb`
- 문서: `app/models/CLAUDE.md` · `app/controllers/CLAUDE.md` · `app/views/CLAUDE.md` · `config/CLAUDE.md` · `test/CLAUDE.md` · `docs/CLAUDE.md`
- `_report_detail` **미변경**(D1 유지), 마이그레이션 **없음**(AC 8).

**계획 대비 편차 1건 — rescue 가 `LoadError`도 잡는다**
§2.3 스케치의 `rescue => e`(= `rescue StandardError`)는 §1.4 pre-mortem 3 이 명시한 **"vips 부재" 시나리오를 실제로는 못 막는다**. libvips 미설치 호스트에서 `.processed` 는 ruby-vips 로딩 시점의 **`LoadError`(< `ScriptError`, `StandardError` 아님)** 를 던져 rescue 를 빠져나가 500 이 된다(개발 호스트에서 재현 확인). AC B2("variant 실패 시 원본 폴백으로 500 없음")를 충족시키려면 `rescue StandardError, LoadError` 가 필요해 그렇게 구현했다. **rescue 의 스코프는 계획대로 `authorize` 이후 처리 구간에만 국한**되므로 fail-closed 성질(AC B3)은 그대로다 — 비인가 요청은 rescue 에 도달조차 하지 않는다(테스트가 variant 호출 0 회 + 403 유지로 단언).

**검증 결과**
- `bin/rails test` — **1564 runs, 12446 assertions, 0 failures / 0 errors / 0 skips**(방송·OCR 파이프라인 회귀 포함 전량 그린).
- `bin/rubocop` — 550 files, no offenses. `bin/brakeman -q` — 0 security warnings(신규 컨트롤러·`send_data`·라우트 포함).
- **테스트 환경 주의**: 이 저장소의 개발/CI 호스트에는 libvips 가 없어 실 variant 처리를 탈 수 없다. 그래서 바이트 서빙 테스트는 `ActiveStorage::Attachment#variant` 를 시임으로 가로채, 컨트롤러가 요청한 유계 크기(512/1600)와 실패 폴백을 **libvips 유무와 무관하게 결정적으로** 검증한다. 실 vips 경로의 화질·용량 확인은 아래 수동 e2e 몫이다.

**남은 수동 확인(§4)**: `docker compose up`(libvips 포함) 환경에서 실제 사진 OCR → 교사·학생 512 표시 + 확대 → **검토 화면 5분 이상 유지 후 이미지 정상 로드**(urls_expire_in 미설정 회귀), HEIC 등 비-variable 업로드 시 클라 canvas 압축의 JPEG 정규화 여부(ADR Consequences).

**후속(범위 밖, 미착수)**: 원본 retention/purge 정책 — §6 Follow-ups.

