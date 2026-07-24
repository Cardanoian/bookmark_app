# app/controllers/librarian/ — 사서 영역

사서(또는 총괄)가 학교 도서관을 운영하는 도구입니다. 전교 독서 현황 대시보드, 이달의 책·행사 관리,
인기대출 집계(정보나루 API 동기화 / 교육청 DLS CSV 업로드)를 담당합니다.
모든 컨트롤러가 `Librarian::BaseController` 를 상속해 `require_librarian!` 역할 게이트와
자기 학교 경계(`current_school`)를 공유합니다. 타역할·타학교 접근은 403/404 로 차단됩니다.

## 파일
- `base_controller.rb` — 네임스페이스 가드. `require_librarian!`(사서/총괄 외 403) + `current_school`(소속 학교 경계, 총괄은 `school_id` 파라미터로 선택) + `verify_authorized` 스킵.
- `dashboards_controller.rb` — 사서 대시보드(`show`). 전교 독후감/독자 수 + 인기대출(학교+전국 NULL) + 이달의 책·행사.
- `events_controller.rb` — 이달의 책·행사 CRUD. 자기 학교로만 스코프(타학교 접근 404).
- `loans_controller.rb` — 인기대출: 목록·수동입력(`index`/`create`) + `sync_data4library`(정보나루 전국 동기화, 무키 시 CSV 폴백 안내) + `import_csv`(DLS CSV 업로드).

## 패턴·규칙
- **역할 게이트 + 학교 경계**: `require_librarian!` 로 사서/총괄만 통과하고, 모든 조회·수정은 `current_school` 로 스코프한다(경계 밖 리소스는 노출/수정 불가).
- **인가 방식**: 네임스페이스 전체가 역할 게이트로 일괄 인가되어 `verify_authorized` 스킵(per-action Pundit 아님).
- **외부 연동 폴백**: 정보나루 키가 없으면 CSV 업로드로 우회 안내. CSV 는 외부 gem 없이 자체 RFC 4180 파서(`parse_csv`)로 처리(Ruby 4.0 csv stdlib 미번들). upsert 는 [school_id, book_title, period] 로 멱등.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
