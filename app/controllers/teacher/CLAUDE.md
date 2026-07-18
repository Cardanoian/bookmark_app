# app/controllers/teacher/ — 담임교사 영역

담임교사(또는 총괄)가 담당 학급을 운영하는 도구 모음입니다. AI 첨삭 완료 독후감의 검토 큐·5축 조정·승인·진위확인,
학생 관리, 학급 미션·퀴즈·루브릭 설정, 그리고 대회요건용 CSV·인쇄 문서 출력을 담당합니다.
대부분 `Teacher::BaseController` 를 상속해 `require_teacher!` 역할 게이트와 담임 학급 소유 검증(경계)을 공유합니다.

## 파일
- `base_controller.rb` — 네임스페이스 가드 + 공통 헬퍼. `require_teacher!`(교사/총괄 외 403) + `teacher_classrooms`·`owned_classroom!`·`owned_student!`·`axis_averages`. **`axis_averages` 는 다형(#3)**: Relation 이면 `SUM(COALESCE(json_extract(rubric,'$.axis'),0)) / count` **SQL 1쿼리**(행 미인스턴스화), Array 면 인메모리 집계(이미 로드된 슬라이스 재사용). 두 경로 값 동일(parity 테스트).
- `dashboards_controller.rb` — 교사 대시보드(`show`). 독후감 통계·5축 평균·약점 인사이트·향상도·검토 큐 요약(SQL 집계로 경량 로드). 5축 평균은 Relation 을 `axis_averages` 에 넘겨 SQL 경로를 탄다(별도 rubric 행 로드 제거). **무게이트 롤아웃 사후 검토(교사 알림)**: 담임 학급 학생이 신고한 온디맨드 게임 콘텐츠(`QuizReport`)를 "🚩 신고된 게임 콘텐츠" 섹션에 노출한다(1건만 있어도 사후 점검, 2건이면 자동 숨김).
- `reviews_controller.rb` — 검토 큐(`index`)·수정(`update`, 5축 ±조정+코멘트)·승인(`approve`)·일괄승인(`batch_approve`)·진위확인(`verify`). 승인 시 뱃지·진화 재계산 + **몬스터 해금 재평가**(`evaluate_monster_unlocks`, flash 안내). 등급을 바꾸는 `update`도 저장 직후 동일하게 재평가한다.
- `students_controller.rb` — 담임 학급 학생 관리(`index`/`create`/`destroy`) + `reset_password`·`give_points`(수동 포인트).
- `missions_controller.rb` — 담임 학급 독서 미션 CRUD(제목·도서·기간). 소유 학급만 배정.
- `quizzes_controller.rb` — 학급 퀴즈 CRUD + 도서 선택 시 `Ai::QuizDraftService` 초안 문항 생성 → 검수 후 published. **도서 선택은 전량 로드 `collection_select` 대신 공용 도서 자동완성(`books#autocomplete`)**을 쓰고, `create`/`update`는 넘어온 `book_id`가 실제 비-searched `Book`인지 서버에서 검증한다(위조·searched 캐시 주입 차단).
- `rubric_configs_controller.rb` — 학급 루브릭 5축 가중치 설정(`edit`/`update`). 0..5 클램프, 채점에 반영.
- `exports_controller.rb` — 독후감 사전·사후 5축 비교 원자료 CSV(`reports_csv`). gem 없이 RFC 4180 인코딩.
- `prints_controller.rb` — 인쇄용 HTML(`layout "print"`): `award`(표창장)·`home_letter`(가정통신문)·`portfolio`(포트폴리오)·`class_report`(학급 리포트).

## 패턴·규칙
- **역할 게이트**: `Teacher::BaseController#require_teacher!` 가 교사/총괄 외 전 역할을 403 으로 차단하고, `verify_authorized` 를 스킵한다(per-action Pundit 아님).
- **학급 경계**: 학급·학생·미션·퀴즈 접근은 `owned_classroom!`/`owned_student!` 로 담임 소유를 검증한다(타 학급 주입 시 403). 생성 시점에만 학급을 고정하고 update 에서 `classroom_id` 재배정을 막는다.
- **예외 — `reviews_controller.rb`**: 유일하게 `ApplicationController` 를 직접 상속하며, per-action `authorize ... ReportPolicy`(review?/approve?/verify?)로 인가한다. index·batch_approve 만 `ensure_reviewer!` 역할 게이트 + `verify_authorized` 스킵.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
