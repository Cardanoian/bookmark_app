# app/controllers/school_admin/ — 교무관리자 영역

교무관리자(또는 총괄)가 자기 학교 단위로 독서교육 현황을 파악하는 도구입니다.
전교 통계(참여율·학급/학년별 5축 평균·약점 진단)와 NEIS 생기부 독서활동상황 자동요약을 담당합니다.
모든 컨트롤러가 `SchoolAdmin::BaseController` 를 상속해 `require_school_admin!` 역할 게이트와
자기 학교 경계(`current_school`)를 공유합니다. 타학교 데이터는 노출되지 않습니다.

## 파일
- `base_controller.rb` — 네임스페이스 가드 + 공통 헬퍼. `require_school_admin!`(교무/총괄 외 403) + `current_school`(소속 학교 경계, 총괄은 `school_id` 파라미터) + `axis_averages`(5축 집계) + `verify_authorized` 스킵. **`axis_averages` 는 다형(#3)**: Relation 이면 `SUM(COALESCE(json_extract(rubric,'$.axis'),0)) / count` **SQL 1쿼리**(전교 규모에도 행 미인스턴스화·상수 메모리), Array 면 기존 인메모리 집계(이미 로드된 학급/학년 슬라이스 재사용). 두 경로는 값이 동일(parity 테스트). `stats#show` 의 전교 평균은 Relation 을 넘겨 SQL 경로를 탄다.
- `stats_controller.rb` — 전교 통계(`show`). 자기 학교 참여율 + 학급별·학년별 5축 평균 + 최저축 약점 진단(성취기준·추천활동).
- `neis_controller.rb` — NEIS 생기부 자동요약(`index`). 학생 선택 시 독후감에서 독서활동상황 문장을 오프라인 템플릿(3인칭 문어체)으로 생성(API 키 불필요).

## 패턴·규칙
- **역할 게이트 + 학교 경계**: `require_school_admin!` 로 교무관리자/총괄만 통과하고, 모든 집계는 `current_school` 로 스코프한다(타학교 미노출).
- **인가 방식**: 네임스페이스 전체가 역할 게이트로 일괄 인가되어 `verify_authorized` 스킵(per-action Pundit 아님).
- **5축 도메인**: 통계·요약은 `ReadingDomain`(RUBRIC_AXES·AXIS_LABELS·ACHIEVEMENT_STANDARDS·RECOMMENDED_ACTIVITIES) 상수를 공유해 축 라벨·성취기준·추천활동을 매핑한다. 전교 집계는 **여러 학년을 섞으므로** 학년군 분기 대신 flat 기본 상수(=5~6학년군)를 그대로 쓴다(성취기준 코드는 대표 표기). 학년군 분기는 학생 개별 리포트 첨삭 경로에만 적용된다.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
