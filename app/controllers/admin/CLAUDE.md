# app/controllers/admin/ — 총괄관리자(superadmin) 전용 /admin 네임스페이스

총괄관리자만 접근하는 전역 관리 화면입니다. 전 학교 통계, 전역 카탈로그(도서·퀴즈·뱃지·상점·몬스터 종) CRUD,
사용자·학교 관리, 콘텐츠 모더레이션, 시스템 설정을 담당합니다. 모든 컨트롤러가 `Admin::BaseController` 를
상속해 `require_superadmin!` 역할 게이트를 통과하며(superadmin 외 전 역할 403), `layout "admin"` 을 사용합니다.

## 파일
- `base_controller.rb` — 네임스페이스 가드. `require_superadmin!`(그 외 403) + `layout "admin"` + `verify_authorized` 스킵(역할 게이트 인가) + **공통 페이지네이션 `paginate(scope, per_page:)`**(각 컨트롤러 `PER_PAGE` 기본, `[page, has_next?, records]` 반환, #misc: admin 무페이지네이션 해소).
- `analytics_controller.rb` — 전교 통합 통계(`show`) + 원자료 CSV 내보내기(`export`, gem 없이 RFC 4180 직접 인코딩). `/admin` 루트.
- `badges_controller.rb` — 전역 뱃지 카탈로그 CRUD.
- `books_controller.rb` — 전역 도서 카탈로그 CRUD(제목 검색). index 페이지네이션(PER_PAGE=50).
- `recommendation_imports_controller.rb` — 공식 추천도서 XLSX 관리(index/create). 업로드 파일에서 어린이 분과만 트랜잭션으로 교체하고, 현재 목록·최근 업로드 이력을 표시한다. 실패 시 기존 활성 목록을 보존한다.
- `game_contents_controller.rb` — **게임 콘텐츠 에스컬레이션(게임 재구성 Phase 3 §4.5)**. 전국 노출되는 **system 풀 퀴즈**의 신고 콘텐츠(reported 또는 reports_count>0)를 총괄이 `index`(전국 관점 검토 큐, 페이지네이션 PER_PAGE=25)·`hide`(영구 숨김 reported=true→fetch_ready 제외)·`restore`(복원 reported=false)·`destroy`(영구 삭제, dependent 자식 정리)한다. 담임 대시보드(자기 학급 신호)와 별개의 전국 중앙 처리 계층. 기존 2인 자동숨김(`record_report!`)은 유지.
- `moderation_controller.rb` — 게시판·토론·토픽 신고/숨김 관리(`index`/`hide`/`unhide`). `kind` 파라미터로 대상 모델 분기. **index 는 3섹션(board/forum/topic)을 통짜 로드하지 않고 각각 독립 page 파라미터(`board_page`/`forum_page`/`topic_page`)로 페이지네이션**(`paginate_section`, PER_PAGE=25, #4).
- `monster_species_controller.rb` — 몬스터 종·진화 규칙 CRUD(element/rarity, evolves_from, evolve_condition JSON).
- `quizzes_controller.rb` — 전역(global) 퀴즈 CRUD. 문항 중첩 폼, 보기(choices)는 줄바꿈 텍스트 → 배열 정규화. index 페이지네이션(PER_PAGE=50).
- `schools_controller.rb` — 학교 전역 CRUD(이름 검색). index 페이지네이션(PER_PAGE=50).
- `account_links_controller.rb` — **계정 연동(MERGE) 총괄 보조(account_linking_seasons_plan §Phase 4)**. `index`(전 학교 병합 감사 목록 + 생존자 이름 검색, 페이지네이션 PER_PAGE=25 — **PII 경계: `snapshot` 원본[password_digest·이름]은 뷰에 절대 덤프하지 않고 요약(moved_counts·from/to·수행자·시각·reversed)만 렌더**)·`create`(임의 병합, 총괄 전권 — id 로 old/new 지정, 서비스가 학년도·정지·학생 가드)·`reverse`(member — **시간창 무제한**, `AccountMerge#reverse!`). 되돌리기 시간창 제한은 교사(14일)에만 있고 총괄은 없다.
- `settings_controller.rb` — 시스템 설정(`show`/`update`): feature_flags·default_rubric_weights·seasonal_banner. API 키류 저장 금지(스크럽).
- `shop_items_controller.rb` — 케어/진화 상점 아이템 CRUD. effect 는 JSON 텍스트로 안전 파싱.
- `users_controller.rb` — 사용자 관리 CRUD + `suspend`/`unsuspend`·`reset_password`·`role`. role/suspended 는 전용 액션만(대량할당 차단). **포인트(:points)도 대량할당에서 제외**하고, update 시 목표값과의 차액을 `award_points` 델타(양수)·`spend_points!`(음수)로 조정해 뱃지·진화·랭킹 후크를 태운다(#9, raw 대입 우회 금지). **목표값은 0 이상 정수만 허용**(음수·소수·문자는 저장 없이 정확히 거부)하고 `spend_points!` 실패(잔액 초과) 시 거짓 "수정했어요" 대신 정직히 안내한다(후속 정밀화). index 페이지네이션(PER_PAGE=50).

## 패턴·규칙
- **역할 격리**: `Admin::BaseController#require_superadmin!` 가 1차 게이트 — superadmin 외(교무관리자 포함) 전 역할을 `Pundit::NotAuthorizedError`(403)로 차단한다.
- **인가 방식**: 네임스페이스 전체가 역할 게이트로 일괄 인가되므로 `skip_after_action :verify_authorized`(per-action Pundit 아님).
- **CRUD 컨벤션**: 표준 7액션 + `set_*` before_action + `*_params` strong parameters. JSON 컬럼(effect·evolve_condition·feature_flags)은 파싱 실패 시 크래시 대신 오류 메시지.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
