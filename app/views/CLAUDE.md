# app/views/ — ERB 뷰 (리소스별 화면 + 역할별 레이아웃)

컨트롤러가 렌더하는 모든 ERB 템플릿이 리소스 디렉토리 단위로 모여 있습니다. 학생·교사·사서·학교관리자·총괄관리자 5개 역할의 화면이 공존하며, 역할별 레이아웃(application·admin·print·mailer)으로 감쌉니다. 부분 화면은 partial(`_이름.html.erb`), 비동기 부분 갱신은 turbo_stream(`.turbo_stream.erb`)으로 응답합니다.

## 파일 / 하위 리소스
- `admin/` — 총괄관리자 콘솔. analytics·badges·books·moderation·monster_species·quizzes·schools·settings·shop_items·users의 index/show/new/edit + `_form` CRUD 화면. 목록 페이지네이션은 공통 `admin/shared/_pager`(검색·필터 파라미터 유지) + `admin/moderation/_pager`(섹션별 독립 page) 사용(#4·#misc).
- `board_posts/` — 학급 게시판. 목록·상세 + `_board_post`·`_cheer_button`·`_sticker` partial
- `books/` — 도서 목록·상세 + `_book_card` partial
- `challenges/` — 챌린지(도전과제) 목록·상세
- `cheers/` — 응원 반영 `update.turbo_stream.erb`(turbo_stream 전용)
- `dashboard/` — 역할별 대시보드(`student`·`teacher`·`librarian`·`school_admin`). 총괄관리자(superadmin)는 별도 대시보드 없이 `dashboard#show`에서 `/admin` 콘솔로 리다이렉트한다.
- `forum_post_likes/` — 토론 글 좋아요 반영 `update.turbo_stream.erb`(turbo_stream 전용)
- `games/` — 독서게임 5종(Phase 3 온디맨드 + 소셜). `catalog/index`(도서→게임 진입 관문 — 공용 `shared/student_nav` 렌더[`active: :games`], 학생 네비 "게임" 탭의 목적지) + 실동작 show: mcq 계열 `quiz`·`classic`(`_quiz_form` 재사용, 4지선다), `vocab`(`_matching_form`, 짝짓기 — **정답 쌍맵 무유출**, 선택 인덱스만 전송), `whoami`(hint_reveal — 서버 상태의 공개 힌트만 렌더, 정답·잔여수 무유출, 힌트 공개는 `button_to`→`whoami#reveal_hint` 서버 렌더 진행), `book/play`(**책 소개 대결** — 도서별 소개 목록[득표순·`button_to` 투표/취소]·작성 폼·정적 작성 가이드, 퀴즈 파이프라인 밖 소셜). 공용 `_regenerate`(다시 뽑기 버튼 + "포인트는 최고 기록만 반영" 안내, 퀴즈 4종 system 판만).
- `layouts/` — 역할별 레이아웃. `application`(기본)·`admin`(관리자 사이드바)·`print`(인쇄 전용, `@media print`)·`mailer`(html/text)
- `learn/` — 학습 홈(index)
- `librarian/` — 사서 화면. `dashboards`·`events` CRUD·`loans`(대출 목록)
- `missions/` — 미션 목록·상세
- `monsters/` — 몬스터 도감·상세 + `_active_monster`·`_detail`·`_dex_grid`·`_evolution_roadmap`·`_monster_card` partial. 보유·도달한 폼은 `monster_sprite`로 애니메이션 WebP를 렌더하고, 에셋 누락 시 이모지로 폴백한다.
- `ocr/` — OCR 결과 반영 `create.turbo_stream.erb`(turbo_stream 전용)
- `purchases/` — 구매 처리 `create.turbo_stream.erb`(turbo_stream 전용)
- `pwa/` — PWA 자산. `manifest.json.erb`·`service-worker.js`
- `rankings/` — 랭킹 화면 + `_podium`·`_ranking_row` partial. 전국(`nation`) 탭은 Top100 + 본인이 Top100 밖이면 "우리 학교" 행을 별도 표기.
- `registrations/` — 회원가입 `new`. 학교 선택은 `schools/_picker` partial 렌더(전량 select 아님).
- `reports/` — 독후감 CRUD + `_form`·`_rubric`·`_ocr_upload`·`_body_field`·`_report`·`_report_detail` partial. 목록 `_report`는 작성 학생에게 확인창이 있는 삭제 버튼을 제공하며, 교사 승인 방송에서도 버튼을 유지한다. **상세(`show`)는 제자리 '수정' 버튼 없이 고쳐쓰기 단일 경로**이고, 상태 의존 영역을 `_report_detail`(local: report, 루트 `dom_id(report, :detail)`)로 분리해 `turbo_stream_from @report` 구독 + AiReviewJob 방송으로 **첨삭/재첨삭 완료를 새로고침 없이 라이브 교체**한다(정책 게이트 버튼은 방송 밖 유지).
- `school_admin/` — 학교관리자 화면. `neis`(생기부)·`stats`(통계)
- `schools/` — 학교 선택 하이브리드 피커 `_picker` partial(가입/로그인 공용). 시도/시군구 캐스케이딩 + 이름검색으로 학교 셀렉트를 채우고, `with_classroom: true`(로그인 폼)면 선택 학교의 학급만 스코프 로드.
- `sessions/` — 로그인 표면 3화면. `new`(**안내 인덱스** — 처음 접속 시 학생/교직원 로그인 선택 카드, 폼 없음)·`student_new`(학생 로그인 폼, 학교 선택은 `schools/_picker` partial 렌더 + 학급 드롭다운)·`staff_new`(교직원 이메일·비밀번호 로그인 폼). 로그아웃은 별도 뷰 없이 `DELETE /session`.
- `shared/` — 앱 공통 partial. `_empty_state`·`_seasonal_banner`·`_student_nav`(학생 상단 7메뉴[내 서재·독후감·게임·도감·상점·미션·랭킹] 네비 — `active` 심볼로 현재 탭 강조, `current_user.student?` 가드. 대시보드·독후감·게임 카탈로그·도감·상점·미션·랭킹 페이지가 공용 렌더해 메뉴 전반에서 navbar 유지)
- `shops/` — 상점 상세 + `_shop_item` partial
- `stickers/` — 스티커 부여 `create.turbo_stream.erb`(turbo_stream 전용)
- `teacher/` — 교사 화면. `dashboards`·`missions` CRUD·`prints`(상장·학급리포트·가정통신문·포트폴리오 인쇄물)·`quizzes`·`reviews`(독후감 첨삭)·`rubric_configs`·`students` + `_nav` partial
- `topics/` — 토론 주제 목록·상세 + `_forum_post`·`_like_button` partial

## 패턴·규칙
- **partial**: `_이름.html.erb` 접두. `render "리소스/이름"`으로 재사용하며 공통 UI는 `shared/`에 둠.
- **turbo_stream**: `액션.turbo_stream.erb`는 Turbo Stream 응답 전용. 페이지 전체 리로드 없이 특정 DOM 조각만 갱신(응원·구매·스티커·OCR 등 상호작용).
- **레이아웃**: 컨트롤러 네임스페이스에 맞춰 `admin`/`print`/`mailer` 레이아웃을 명시 지정, 그 외 화면은 `application` 사용.
- **역할 뷰**: 같은 개념(대시보드·미션·퀴즈)도 역할별 폴더(`teacher/`·`librarian/`·`school_admin/`·`admin/`)에 분리해 권한·화면을 격리.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
