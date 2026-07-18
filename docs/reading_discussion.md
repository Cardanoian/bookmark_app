# 독서 토론(Reading Discussion) — 설계·구현 문서

## 배경 / 해결한 문제

몬스터 도감 dex 03(뾰족이, `pencil_1`)의 해금 조건은 `topic_posts`(작성한 토론 글 수)이고
진화 조건은 `{ points: 150, topic_posts: 2 }`이다. 그러나 토론 스택(`Topic`/`ForumPost`/
`ForumPostLike` + 컨트롤러·정책·라우트·관리자 모더레이션)은 존재하되 **학생 상위 메뉴 5개
재편(menu_refactor) 이후 진입점이 하나도 없어** 학생이 `/topics`에 도달할 수 없었다. 결과적으로
학생은 토론 글을 쓸 수 없어 **dex 03 라인이 영구 획득·진화 불가**한 고아 상태였다.

이 작업은 전면 재작성이 아니라 **고아 스택의 표면화 + 아동 안전 최소 보강**이다.

## 설계 결정(Option B)

| 축 | 결정 | 근거 |
|---|---|---|
| 진입점 | 6번째 상위 메뉴 없이 **책 앵커드(독서활동 화면)** + **홈 카드** + 토론 뷰에 학생 nav 복원 | 5메뉴 불변식(menu_refactor) 존중 |
| 데이터 | 전량 additive(`forum_posts.reports_count`·`hidden_by_id`, `topics.hidden_by_id`, `forum_post_reports`) | 기존 데이터 무손상, `topic.book_id`는 이미 존재 |
| 도달성 | 글 작성 시 기존 `evaluate_monster_unlocks` 트리거가 그대로 동작 | dex 03 경로 실제 폐합 |
| 교사 경계 | `Classroom.teacher_id` 기준(교사는 `classroom_id`가 nil) | 담임이 자기 반 토픽 열람·개설·모더레이션 가능 |
| 안전 | 금칙어(FORUM 리스트)·길이·신고·교사 모더레이션 | 저학년 UGC 안전 1급 |
| 자동숨김 | **없음**(신고→교사 검토만) | 또래 저작물 집단신고 괴롭힘 벡터 차단 |
| 신고 라우팅 | **저자 학급** 담임 대시보드 | 담임 모더레이션 권한과 정합 |
| 롤아웃 | `reading_discussion` 스코프 기능 플래그(컨트롤러 강제, 기본 확대) | kill switch 실효 + 학급 격리 |

## 아동 안전 계층

1. **작성 게이트** — 금칙어(`Moderation::TextDenylist::FORUM`, `새끼`·`꺼져` 등 오탐 낱말 제외) +
   길이(글 2..500 / 제목 2..60). 저장 거부는 대면 실패이므로 명백한 욕설만 하드블록.
2. **신고** — 1인 1신고(`(forum_post, user)` unique), 자기 글 신고 불가. **자동 숨김 없음**.
3. **교사 감독** — 저자 학급 담임 대시보드 "신고된 토론 글" 노출 + 수동 숨김/해제
   (`Teacher::ForumModerations`, `owned_student!` 저자 학급 경계).
4. **총괄 모더레이션** — 기존 `Admin::Moderation`(hide/unhide, `hidden_by` 귀속).
5. **hidden 격리** — 신규 조회 전부 `.visible`/`policy_scope` 경유(학생 화면 비노출).
6. **kill switch** — `reading_discussion` 플래그를 컨트롤러에서 강제(전역 false=하드 kill,
   `reading_discussion:classroom:<id>`=false 로 학급 격리).

## 경계 격리(정책 경유)

- 학생: 자기 학급 + 자기 학교 스코프(`TopicPolicy`).
- 교사: 담당 학급(`Classroom.teacher_id`) + 자기 학교 스코프. `user.classroom_id`가 nil이라
  학생 규칙을 재사용하면 담임이 자기 반을 못 보는 버그가 생기므로 별도 분기.
- 신규 조회(`@book_topics`·`StudentHomeQuery#recent_topics`·교사 신고 목록·교사 hide) 모두
  `policy_scope`/`owned_student!`/`Classroom.teacher_id` 경유.

## 잔존 리스크(정직화)

- **채택은 교사 촉진에 의존**한다(5메뉴 유지의 구조적 대가). 주간 활성 토픽 수·참여율을 관측 지표로.
- `topic_posts`는 `.count` 유지(숨김 글도 카운트) — 파밍은 글 작성이 0포인트라 무위험이고,
  `.visible.count`로 좁히면 사후 숨김이 학생 진화 진행을 되돌리는 트레이드오프가 더 커서 기각.

## 관련 파일

- 모델: `app/models/{topic,forum_post,forum_post_report}.rb`, `app/models/app_setting.rb`
- 서비스: `app/services/moderation/text_denylist.rb`, `app/services/student_home_query.rb`
- 정책: `app/policies/{topic_policy,forum_post_report_policy}.rb`
- 컨트롤러: `app/controllers/{topics,forum_posts,forum_post_reports}_controller.rb`,
  `app/controllers/teacher/{dashboards,forum_moderations}_controller.rb`, `application_controller.rb`
- 뷰: `app/views/topics/*`, `reading_activities/show`, `dashboard/student`, `teacher/dashboards/show`
- 테스트: `test/integration/reading_discussion_test.rb`, `test/services/moderation/text_denylist_test.rb`,
  `test/policies/topic_policy_test.rb`
