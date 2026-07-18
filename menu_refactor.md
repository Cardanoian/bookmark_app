# 학생 메뉴·독서활동·미션 재구성 구현 계획

## 0. 문서 목적

이 문서는 학생 경험을 독서 중심으로 단순화하기 위해 다음 네 가지 작업을 하나의 리팩터링으로 추진하는 상세 구현 계획이다.

1. 학생 상위 메뉴를 5개로 재편한다.
2. 홈, 내 서재, 독서활동의 책임을 명확하게 나눈다.
3. 상점·구매·인벤토리·아이템 기반 먹이주기를 완전히 제거한다.
4. 기존 미션을 기간·정량 목표·자동 진행·포인트 보상을 갖춘 학급 미션으로 재설계한다.

이 문서는 구현자가 추가 기획 결정을 최소화하고 바로 작업을 나눌 수 있는 수준을 목표로 한다. 구현 중 데이터 구조나 운영 정책을 변경해야 한다면 이 문서의 결정 기록부터 갱신한다.

---

## 1. 최종 결정 요약

### 1.1 학생 상위 메뉴

학생 상위 메뉴는 다음 5개로 고정한다.

| 순서 | 메뉴     | 권장 경로         | 핵심 질문                               |
| ---- | -------- | ----------------- | --------------------------------------- |
| 1    | 홈       | /                 | 어떤 책을 읽고 무엇을 이어서 할까?      |
| 2    | 내 서재  | /library          | 내가 어떤 책으로 무엇을 했지?           |
| 3    | 독서활동 | /reading_activity | 이 책으로 어떤 활동을 할까?             |
| 4    | 도감     | /monsters         | 어떤 몬스터를 발견했고 어떻게 성장할까? |
| 5    | 랭킹     | /rankings         | 내 독서활동 성과는 어느 정도일까?       |

표시 문구와 아이콘의 기본안은 다음과 같다.

- 홈: 🏠
- 내 서재: 📚
- 독서활동: ✏️
- 도감: 🐾
- 랭킹: 🏆

독후감, 게임, 미션, 상점은 더 이상 학생 상위 메뉴로 노출하지 않는다.

### 1.2 화면별 책임

- 홈은 도서 발견, 추천, 이어하기, 진행 중인 학급 미션 요약을 담당한다.
- 내 서재는 학생 개인의 책별 독서활동 기록을 보여주는 독서 포트폴리오다.
- 독서활동은 책을 먼저 고르고 독후감 또는 게임을 선택하는 실행 허브다.
- 도감은 독서활동으로 얻은 몬스터의 발견·진화 상태를 보여준다.
- 랭킹은 포인트 기반 성과 비교를 유지한다.
- 프로필, 비밀번호 변경, 로그아웃은 공통 학생 헤더의 사용자 영역에 둔다.

### 1.3 상점과 포인트

- 상점 메뉴와 상점 기능을 완전히 삭제한다.
- ShopItem, Purchase, 구매 처리, 인벤토리, 상점 관리자 CRUD를 제거한다.
- 아이템을 소비하는 몬스터 먹이주기도 제거한다.
- User.points, 독후감·게임 포인트, 몬스터 진화 비용, 레벨, 랭킹은 유지한다.
- 포인트 흐름은 독서활동 보상과 미션 완료 보상으로 단순화한다.

최종 포인트 흐름은 다음과 같다.

    독후감 첨삭 또는 게임 완료
        → 기본 활동 포인트
        → 학급 미션 목표 진행
        → 미션 완료 시 보너스 포인트
        → 레벨·도감·진화·랭킹 반영

### 1.4 미션

- 미션은 담임교사가 담당 학급에 만드는 기간제 목표다.
- 교사는 기간, 하나 이상의 목표, 완료 보상 포인트를 설정한다.
- 1차 지원 목표는 승인된 독후감 수와 유효 게임 완료 수다.
- 학급 학생은 별도 참여 버튼 없이 자동 배정된다.
- 모든 목표는 AND 조건으로 판정한다.
- 학생별 진행도를 자동 계산한다.
- 기간 안에 생성된 활동만 인정한다.
- 독후감은 기간 안에 제출되고 최종적으로 교사 승인된 원본 독후감만 인정한다.
- 게임은 기간 안에 GamePlay 원장에 정상 기록된 완료 건만 인정한다.
- 보상은 학생별·미션별 정확히 한 번만 지급한다.
- 미션 참여 횟수를 사용하는 몬스터 조건은 앞으로 완료한 미션 수를 기준으로 계산한다.
- 미션은 상위 메뉴로 만들지 않고 홈과 독서활동에 노출한다.

---

## 2. 목표와 비목표

### 2.1 목표

- 학생이 다섯 개 메뉴만 보고 서비스 구조를 이해할 수 있게 한다.
- 책 발견 → 활동 선택 → 활동 수행 → 기록 축적 → 성장 확인의 흐름을 만든다.
- 독후감과 게임의 중복된 책 선택 경험을 하나의 독서활동 허브로 합친다.
- 내 서재를 단순 도서 목록이 아닌 책별 활동 기록으로 만든다.
- 상점 경제 시스템을 제거하여 핵심 독서 경험과 유지보수 비용을 줄인다.
- 미션을 실제로 측정 가능하고 보상이 명확한 학급 목표로 바꾼다.
- 포인트 이중 지급, 기간 경계 오류, 학급 간 데이터 노출을 방지한다.
- 기존 데이터가 있는 환경에서도 단계적으로 배포할 수 있게 한다.

### 2.2 이번 작업의 비목표

- 도서 찜, 읽고 싶은 책, 대출 상태를 관리하는 별도 UserBook 모델은 만들지 않는다.
- 개인화 추천 AI나 외부 추천 API를 새로 도입하지 않는다.
- 새로운 게임 종류를 추가하지 않는다.
- 랭킹 계산 방식과 몬스터 진화 비용을 전면 재설계하지 않는다.
- 전역·학교 단위 Challenge 기능은 이번 미션 개편에 합치지 않는다.
- 교사가 직접 학생별 보상을 임의 지급하는 별도 기능은 만들지 않는다.
- 종료된 미션의 포인트를 회수하는 기능은 만들지 않는다.
- 미션 목표로 특정 장르, 연속 일수, 특정 게임 종류를 지원하는 것은 후속 범위로 둔다.

---

## 3. 현재 구조와 해결해야 할 문제

### 3.1 현재 학생 메뉴

현재 app/views/shared/_student_nav.html.erb에는 다음 7개 메뉴가 있다.

- 내 서재
- 독후감
- 게임
- 도감
- 상점
- 미션
- 랭킹

현재 root는 DashboardController#show이며 학생 대시보드는 실제로 내 서재라는 제목을 사용한다. 최근 독후감, 활성 몬스터, 포인트가 한 화면에 섞여 있다. 독후감과 게임은 각각 별도의 메뉴에서 책을 선택한다.

해결 방향:

- root 화면을 명확한 홈으로 바꾼다.
- 내 서재를 별도 경로와 화면으로 분리한다.
- 독후감과 게임의 시작점을 독서활동으로 합친다.
- 미션은 홈·독서활동의 문맥형 카드로 이동한다.

### 3.2 현재 내 서재의 한계

현재 별도 내 서재 리소스는 없고 학생 대시보드가 내 서재 역할을 겸한다. 책별 활동을 묶지 않고 최근 독후감만 표시한다. GamePlay는 내 서재에 표시되지 않는다.

해결 방향:

- Book을 기준으로 Report와 GamePlay를 집계한 읽기 전용 요약을 제공한다.
- 책 연결이 없는 기존 독후감도 잃지 않고 별도 레거시 항목으로 표시한다.
- 별도의 영속 UserBook 테이블 없이 기존 활동 원장을 이용한다.

### 3.3 현재 독서활동의 한계

- 독후감은 ReportsController와 reports 화면에서 시작한다.
- 게임은 Games::CatalogController와 games/catalog 화면에서 시작한다.
- 두 기능 모두 책 선택이 필요하지만 진입점과 인터페이스가 분리돼 있다.

해결 방향:

- 독서활동 화면에서 책을 한 번 선택한다.
- 선택한 책을 독후감 작성과 5종 게임 진입에 공통으로 전달한다.
- 기존 report 및 games 실행 라우트는 실제 작업 라우트로 유지하되 학생 메뉴의 정식 진입점은 독서활동 하나로 통일한다.

### 3.4 현재 상점의 범위

상점은 메뉴 하나만의 기능이 아니다.

- ShopItem 카탈로그
- Purchase 인벤토리
- 상점 조회와 구매
- 포인트 차감
- 몬스터 먹이주기와 케어 JSON
- 관리자 상점 아이템 CRUD
- 상점 시드 태스크
- 관련 테스트와 사용자 매뉴얼

메뉴만 숨기면 사용되지 않는 모델·테이블·라우트가 남고 몬스터 상세에 상점 의존성이 계속 존재한다. 따라서 전체 수직 기능을 삭제해야 한다.

### 3.5 현재 미션의 한계

현재 미션은 참여 버튼을 누르면 session[:active_mission_id]를 저장하고, 다음에 작성하는 독후감의 reports.mission_id에 연결한다.

문제점:

- 독립적인 참여 또는 진행 상태 모델이 없다.
- 참여 버튼을 누르는 것을 잊으면 활동이 집계되지 않는다.
- 미션 기간이 화면 배지에만 사용되고 참여를 제한하지 않는다.
- 목표 수량을 설정할 수 없다.
- 게임 활동을 목표로 사용할 수 없다.
- 미션별 직접 포인트 보상이 없다.
- 선택 도서가 있어도 해당 책의 독후감인지 검증하지 않는다.
- 같은 미션에 여러 번 참여할 수 있다.
- 저장 실패 시 세션 플래그가 먼저 소비될 수 있다.
- ReadingStats#missions는 연결된 mission_id 수만 센다.

해결 방향:

- 세션과 reports.mission_id를 제거한다.
- MissionGoal과 MissionParticipation을 도입한다.
- 실제 활동 원장에서 기간 내 진행도를 자동 계산한다.
- 완료와 보상 지급을 영속화한다.

---

## 4. 목표 정보 구조와 라우팅

### 4.1 권장 라우트

config/routes.rb의 학생 영역에 다음 단수 리소스를 추가한다.

    root 'dashboard#show'
    resource :library, only: :show
    resource :reading_activity, only: :show

최종 학생 내비게이션 경로:

| active 키        | 라벨     | 경로                  |
| ---------------- | -------- | --------------------- |
| home             | 홈       | root_path             |
| library          | 내 서재  | library_path          |
| reading_activity | 독서활동 | reading_activity_path |
| monsters         | 도감     | monsters_path         |
| rankings         | 랭킹     | rankings_path         |

기존 경로의 처리:

- reports_path는 내 서재 내부의 독후감 전체 목록 또는 호환 경로로 유지할 수 있다.
- new_report_path와 report 상세·수정 경로는 계속 사용한다.
- games_catalog_path는 내부 호환을 위해 한 릴리스 유지한 뒤 reading_activity_path로 리다이렉트하거나, 뷰를 독서활동 공용 partial로 바꾼다.
- missions_path와 mission_path는 상위 메뉴에서 제거하되 상세 링크가 필요하면 유지한다.
- join_mission_path는 새 미션 전환 완료 후 삭제한다.
- shop_path와 purchases_path는 상점 제거 배포에서 삭제한다.

라우트 이름은 구현 전 bin/rails routes로 충돌 여부를 확인한다.

### 4.2 컨트롤러 책임

#### DashboardController#show

학생 홈 데이터만 준비한다.

- 학년 맞춤 추천 도서
- 최근 학급 인기 도서
- 마지막 활동 이어하기
- 진행 중인 미션 요약
- 활성 몬스터와 포인트의 작은 요약

교사·교무·사서·총괄관리자의 기존 역할별 분기는 유지한다.

#### LibrariesController#show

현재 학생의 책별 활동 요약을 조회한다.

- 필터
- 페이지네이션
- 책별 독후감 수
- 책별 게임 완료 수
- 최근 활동 시각
- 독후감 검토 상태 요약
- 책 연결이 없는 레거시 독후감

#### ReadingActivitiesController#show

책 선택과 활동 선택을 담당한다.

- book_id가 없으면 책 검색·선택 상태
- book_id가 유효하면 선택한 책과 활동 선택 카드
- 해당 책의 최근 내 활동
- 미션 진행에 반영될 수 있는 활동 안내

존재하지 않거나 searched 캐시 정책상 허용되지 않는 book_id는 무시하고 책 선택 상태로 되돌린다. 다른 학생의 개인 데이터는 절대 book_id만으로 조회하지 않는다.

---

## 5. 화면 상세 설계

### 5.1 홈

학생 홈의 목적은 새로운 책을 발견하고, 중단한 활동과 현재 미션을 빠르게 이어가는 것이다. 전체 기록을 홈에 다시 복제하지 않는다.

#### 권장 섹션 순서

1. 환영 및 이어하기
2. 진행 중인 우리 반 미션
3. 내 학년 추천 도서
4. 우리 반 또는 학교에서 많이 활동한 책
5. 활성 몬스터·포인트 요약

모바일에서는 위 순서를 그대로 세로 배치한다. 데스크톱에서는 이어하기와 미션을 상단 2열로 만들 수 있지만 DOM 순서는 모바일 읽기 순서를 따른다.

#### 이어하기

우선순위:

1. AI 첨삭 대기 또는 교사 승인 대기 독후감
2. 가장 최근에 고쳐쓰기 중인 독후감
3. 가장 최근 활동한 책으로 새 활동 시작
4. 활동 이력이 없으면 독서활동 시작 CTA

CTA 문구는 상태를 숨기지 않는다.

- 첨삭 결과 확인
- 교사 승인 기다리는 중
- 고쳐쓰기 이어서 하기
- 이 책으로 다시 활동하기
- 첫 독서활동 시작하기

#### 추천 도서 v1 규칙

외부 개인화 API를 추가하지 않고 현재 Book 데이터로 결정적인 추천을 만든다.

1. 학생 학년을 초등 1~2, 3~4, 5~6 학년군으로 변환한다.
2. Book.recommended 중 grade_band가 학생 학년군과 일치하는 도서를 우선한다.
3. 이미 Report 또는 GamePlay 활동이 있는 책은 신규 추천에서 뒤로 보낸다.
4. 결과가 부족하면 같은 학년군의 classic, 전체 recommended 순으로 보충한다.
5. 정렬은 운영자가 재현할 수 있도록 title 또는 고정된 일일 seed를 사용한다.

무작위 SQL 정렬은 페이지마다 결과가 흔들리고 대규모 카탈로그에서 비싸므로 사용하지 않는다.

#### 인기 도서 v1 규칙

- 최근 30일 내 같은 학급 학생의 Report와 GamePlay를 book_id 기준으로 합산한다.
- 학급 데이터가 부족하면 같은 학교, 그다음 전체 데이터로 폴백한다.
- book_id가 없는 활동은 인기 도서 계산에서 제외한다.
- 한 학생의 반복 활동이 순위를 과도하게 지배하지 않도록 사용자별·책별 일일 활동 상한을 적용하는 것을 권장한다.

첫 구현에서 쿼리가 복잡해지면 학급 내 최근 승인 독후감의 distinct book_id 집계만으로 시작하고 GamePlay 합산을 후속 최적화할 수 있다.

#### 홈 빈 상태

- 추천 도서가 없으면 책 검색 CTA를 보여준다.
- 진행 중인 미션이 없으면 미션 영역 전체를 숨기거나 작은 안내만 표시한다.
- 활성 몬스터가 없으면 기존 스타터 선택 CTA를 유지한다.
- 추천 실패가 홈 전체 오류로 이어지지 않도록 각 섹션을 독립적으로 폴백한다.

### 5.2 내 서재

내 서재는 개인 독서 포트폴리오다. 저장해 둔 책이 아니라 실제 활동한 책을 기준으로 구성한다.

#### 기본 목록 단위

Book 한 권당 카드 한 개를 만든다. 카드에는 다음을 표시한다.

- 표지, 제목, 저자
- 승인된 독후감 수
- 검토 중인 독후감 수
- 게임 완료 수
- 마지막 활동 날짜
- 최근 독후감 상태
- 이 책으로 활동하기 CTA
- 책별 상세 기록 보기 CTA

GamePlay에는 QuizAttempt와의 직접 연결이 없으므로 v1에서는 점수 합계를 억지로 표시하지 않고 완료 횟수만 표시한다.

#### 활동 묶음 계산

Book 연결 활동:

- reports.book_id
- game_plays.book_id

책별 마지막 활동:

- Report.created_at
- GamePlay.played_on의 해당 날짜
- 두 값 중 최신값

책 연결이 없는 기존 Report:

- book_title을 정규화하여 별도 레거시 그룹으로 표시한다.
- 실제 Book과 문자열만으로 자동 결합하지 않는다.
- 가능하면 관리용 데이터 보정 작업으로 book_id를 연결한 뒤 레거시 그룹 수를 줄인다.

#### 필터

v1 필터:

- 전체
- 독후감 있음
- 게임 기록 있음
- 진행 중
- 완료

상태 정의:

- 진행 중: pending, processing 또는 done이지만 reviewed=false인 독후감이 하나 이상
- 완료: 승인 독후감 또는 GamePlay가 하나 이상이며 진행 중 독후감이 없음

활동 종류 필터와 상태 필터가 동시에 필요해지면 쿼리 파라미터를 kind와 status로 분리한다.

#### 정렬과 페이지네이션

- 기본 정렬은 last_activity_at 내림차순이다.
- 동일 시각은 book_id 내림차순으로 안정 정렬한다.
- 페이지당 20권을 기본값으로 둔다.
- 모든 Report와 GamePlay를 Ruby 메모리에 올리지 않는다.
- 집계용 쿼리 또는 전용 query object를 사용한다.

#### 권장 구현 객체

app/queries 또는 app/services에 StudentLibraryQuery를 둔다.

입력:

- user
- kind
- status
- page
- per_page

출력:

- entries
- has_next_page
- legacy_report_groups

entry는 영속 모델이 아닌 ActivityBookSummary 성격의 읽기 전용 객체로 두어도 된다. 새 테이블은 만들지 않는다.

### 5.3 독서활동

독서활동은 책 중심의 실행 허브다.

#### 기본 흐름

    독서활동 진입
        → 책 제목 또는 저자로 검색
        → 책 선택
        → 독후감 쓰기 또는 독서 게임 선택
        → 기존 기능으로 진입

#### 책 미선택 상태

- 로컬 카탈로그 자동완성을 기본으로 사용한다.
- 검색 결과에는 표지, 제목, 저자, 학년군을 표시한다.
- 키보드만으로 검색 결과 이동과 선택이 가능해야 한다.
- 검색 결과가 없을 때 외부 도서 검색 또는 직접 제목 입력으로 이어지는 정책은 기존 독후감 작성 흐름과 일치시킨다.
- 게임은 등록된 Book이 필요하므로 직접 제목만 있는 책은 독후감만 허용할지, 제출 시 Book 등록 후 게임을 열지 명확하게 처리한다.

권장 정책은 독서활동 허브에서는 등록된 Book만 선택하게 하고, 찾지 못한 책은 독후감 작성 화면의 원격 검색·등록 흐름으로 보낸다.

#### 책 선택 상태

선택 도서 카드 아래에 두 개의 큰 활동 카드를 둔다.

##### 독후감 쓰기

- 새 독후감 쓰기
- 작성 또는 첨삭 중 독후감이 있으면 상태 표시
- 최근 승인 독후감 보기
- new_report_path에 검증된 book_id와 book_title을 전달

##### 독서 게임

- 현재 플레이 가능한 게임 5종 표시
- 각 게임의 설명과 최근 완료 여부 표시
- 기존 games_*_play_path에 검증된 book_id 전달
- 게임 콘텐츠 준비 실패 시 기존 오프라인 폴백을 유지

#### 선택 도서 변경

- 선택한 책 제목 옆에 책 바꾸기 버튼을 둔다.
- 쿼리 파라미터 book_id를 제거하여 선택 초기 상태로 돌아간다.
- 브라우저 뒤로가기로 이전 선택 상태가 복구되어야 한다.

#### 미션 문맥

선택한 활동이 진행 중 미션 목표에 포함될 경우 다음 정도의 안내만 보여준다.

- 독후감 1편을 승인받으면 미션 진행도가 올라가요.
- 이 게임을 완료하면 게임 목표에 반영돼요.

아직 완료되지 않은 독후감을 즉시 미션 진행도에 더한 것처럼 표시하지 않는다.

### 5.4 도감

도감의 핵심 구조는 유지한다.

변경 사항:

- 상점과 먹이 관련 링크·선택 UI·안내 문구 제거
- 몬스터 성장은 독서활동, 완료 미션, 포인트 조건으로 설명
- ReadingStats의 missions 의미를 참여 미션 수에서 완료 미션 수로 변경
- 상점 제거 후에도 스타터 선택, 발견, 대표 몬스터, 진화는 유지

UserMonster.care가 먹이주기 외에 사용되지 않는 것이 확인되면 컬럼을 제거한다. monster-care Stimulus 컨트롤러는 현재 진화 축하 애니메이션에도 사용되므로 이름만 보고 삭제하지 않는다.

### 5.5 랭킹

현재 포인트 랭킹을 유지한다.

추가 확인 사항:

- 미션 보너스 포인트가 지급되면 기존 User#award_points 흐름을 통해 랭킹 방송이 발생해야 한다.
- 상점 제거 후 포인트 소비는 주로 몬스터 진화에만 남는다.
- 활동 기본 포인트와 미션 보너스 포인트가 모두 랭킹에 포함된다는 점을 학생과 교사에게 명확히 안내한다.
- 교사별 보상 편차가 랭킹을 왜곡하지 않도록 미션 보상 상한을 서버에서 강제한다.

---

## 6. 학생 내비게이션 구현 상세

### 6.1 shared/student_nav 변경

app/views/shared/_student_nav.html.erb의 nav_items를 5개로 바꾼다.

- active: :home
- active: :library
- active: :reading_activity
- active: :monsters
- active: :rankings

현재 모바일 details 방식과 데스크톱 필 바를 유지할 수 있다. 다만 5개 메뉴는 모바일 하단 내비게이션에도 적합하므로 실제 사용성 검증 후 하단 고정형으로 바꿀 수 있다. 첫 구현에서는 범위를 줄이기 위해 기존 반응형 구조를 유지하고 항목만 재편한다.

### 6.2 활성 메뉴 규칙

- root 학생 홈은 :home
- library_path와 책별 내 기록 화면은 :library
- reading_activity_path, 새 독후감 시작, 게임 선택 화면은 :reading_activity
- report 상세는 활동 결과를 보는 화면이므로 :library 또는 :reading_activity 중 일관된 하나를 정해야 한다.

권장안:

- 새 작성·편집·게임 플레이 과정은 :reading_activity
- 제출 후 결과·기존 기록 상세는 :library

공통 partial에서 경로별 자동 추론하지 말고 각 화면이 active 값을 명시한다.

### 6.3 공통 학생 헤더

- 현재 학생 이름, 마이페이지, 로그아웃을 유지한다.
- 포인트는 헤더에 항상 보여줄 필요는 없으며 홈·도감·랭킹 문맥에서 표시한다.
- 메뉴와 프로필 액션을 중복 배치하지 않는다.

### 6.4 접근성

- nav에 aria-label 학생 메뉴 유지
- 활성 항목에 aria-current=page 유지
- 아이콘은 aria-hidden 처리
- 각 조작부 최소 높이 44px 유지
- 모바일 메뉴 열림 상태가 Turbo 캐시에 남지 않게 기존 close 처리 유지
- 색상만으로 활성 상태를 구분하지 않고 텍스트 굵기와 aria-current를 함께 사용

---

## 7. 상점 완전 제거 계획

### 7.1 제거 대상

#### 라우트

- resource :shop
- resources :purchases
- admin namespace의 resources :shop_items
- monsters의 feed member action

#### 컨트롤러

- app/controllers/shops_controller.rb
- app/controllers/purchases_controller.rb
- app/controllers/admin/shop_items_controller.rb
- MonstersController#feed
- MonstersController의 @foods 조회
- feed_item?와 apply_care

#### 모델과 연관

- app/models/shop_item.rb
- app/models/purchase.rb
- User has_many :purchases
- ShopItem과 Purchase 관련 연관·enum·검증

#### 정책과 헬퍼

- app/policies/purchase_policy.rb
- MonsterPolicy#feed?
- app/helpers/shops_helper.rb
- ApplicationHelper 등에서 shops#show를 가리키는 매핑

#### 뷰

- app/views/shops 전체
- app/views/purchases 전체
- app/views/admin/shop_items 전체
- 학생 nav의 상점 항목
- 관리자 nav의 상점 아이템 항목
- monsters/_detail의 먹이 선택과 상점 링크

#### 시드와 태스크

- db/seeds.rb의 shop_items:seed 호출
- lib/tasks/badges.rake 안의 shop_items namespace
- db/seeds 또는 테스트 픽스처의 ShopItem/Purchase 생성

#### 테스트

- test/integration/shop_purchase_test.rb
- test/integration/monster_feed_test.rb
- gamification_models_test의 ShopItem/Purchase 테스트
- student_nav_persistence_test의 상점 경로·라벨
- admin_content_test의 shop item CRUD
- admin_isolation_test의 admin_shop_items_path
- 상점 응답을 가정하는 기타 테스트

#### 문서

- 학생·관리자 매뉴얼의 상점 절
- README, TODO, DESIGN 문서의 현재 기능 설명
- app, controllers, models, views, helpers, policies, config, db, lib/tasks, test 하위 CLAUDE.md

역사 기록 성격의 TODO 완료 로그나 과거 설계 문서는 내용을 무조건 삭제하지 않는다. 현재 기능을 설명하는 문장과 역사적 기록을 구분해, 역사 문서는 제거됨 표시 또는 새 계획 링크를 남긴다.

### 7.2 유지 대상

- User.points
- Pointable#award_points
- Pointable#spend_points!
- 레벨과 칭호
- 독후감 포인트
- 게임 포인트
- 몬스터 진화 시 포인트 차감
- 랭킹
- 몬스터 발견과 진화
- monster-care Stimulus의 진화 축하 애니메이션

spend_points!는 상점 제거 후에도 몬스터 진화에서 사용하므로 삭제하지 않는다.

### 7.3 데이터베이스 제거

새 마이그레이션을 추가하며 과거 마이그레이션 파일을 수정하지 않는다.

제거 순서:

1. purchases 외래 키와 테이블 제거
2. shop_items 테이블 제거
3. user_monsters.care가 먹이 이외에 사용되지 않으면 컬럼 제거

운영 데이터가 있는 경우:

- 배포 전 DB 백업을 확인한다.
- 구매 이력을 법적·운영상 보존할 이유가 있는지 확인한다.
- 보존이 필요하면 CSV 또는 별도 archive 테이블로 내보낸 뒤 런타임 모델은 제거한다.
- 포인트는 이미 User에 반영되어 있으므로 구매 내역을 삭제해도 현재 잔액은 되돌리지 않는다.

개발·테스트 전용 데이터만 있다면 별도 보관 없이 삭제한다.

### 7.4 배포 안전성

운영 롤링 배포가 있다면 두 단계로 나눈다.

1. 코드에서 상점 접근과 쓰기를 제거하되 테이블은 남기는 호환 배포
2. 이전 코드가 모두 내려간 뒤 테이블을 삭제하는 스키마 배포

단일 인스턴스 개발 환경에서는 한 변경 묶음으로 처리할 수 있지만, 마이그레이션 자체는 되돌림 가능성과 백업 정책을 명시해야 한다.

---

## 8. 미션 도메인 재설계

### 8.1 핵심 개념

#### Mission

담임이 특정 학급에 발행하는 기간제 목표 묶음이다.

#### MissionGoal

미션을 완료하기 위해 달성해야 하는 정량 목표 한 개다. 한 미션에 하나 이상 존재하며 모두 만족해야 한다.

#### MissionParticipation

학생이 해당 미션에 자동 배정됐다는 사실과 완료·보상 지급 상태를 기록한다. 진행 수치는 원장 데이터에서 계산하고 중복될 수 있는 카운터를 저장하지 않는다.

### 8.2 권장 스키마

#### missions

| 컬럼          | 타입         | 제약·의미                             |
| ------------- | ------------ | ------------------------------------- |
| classroom_id  | FK           | 필수, 대상 학급                       |
| created_by_id | User FK      | 생성 교사, 삭제 시 nullify 권장       |
| title         | string       | 필수, 길이 1~80                       |
| description   | text         | 선택, 학생 안내                       |
| start_date    | date         | 필수, Asia/Seoul 기준 시작일          |
| end_date      | date         | 필수, 시작일 이상                     |
| reward_points | integer      | 필수, 기본 0이 아닌 허용 범위         |
| status        | integer enum | draft, published, cancelled, archived |
| published_at  | datetime     | 발행 시각                             |
| cancelled_at  | datetime     | 취소 시각                             |
| timestamps    | datetime     | 기본                                  |

권장 인덱스:

- classroom_id, status, start_date, end_date
- created_by_id

기존 book_id는 이번 목표 모델에서는 제거한다. 특정 도서 목표는 나중에 MissionGoal의 조건으로 추가하는 것이 명확하다. 운영 데이터에 book_id가 존재한다면 제거 전 별도 정책을 적용한다.

#### mission_goals

| 컬럼         | 타입         | 제약·의미                    |
| ------------ | ------------ | ---------------------------- |
| mission_id   | FK           | 필수                         |
| goal_type    | integer enum | approved_reports, game_plays |
| target_count | integer      | 필수, 1 이상                 |
| position     | integer      | 화면 정렬                    |
| timestamps   | datetime     | 기본                         |

인덱스와 제약:

- mission_id, goal_type unique
- target_count > 0 체크 제약
- 한 미션에 같은 목표 종류를 두 번 만들지 않는다.

초기 enum:

- approved_reports: 승인된 원본 독후감 수
- game_plays: GamePlay 원장의 유효 완료 수

#### mission_participations

| 컬럼                  | 타입     | 제약·의미                  |
| --------------------- | -------- | -------------------------- |
| mission_id            | FK       | 필수                       |
| user_id               | FK       | 필수, 학생                 |
| assigned_at           | datetime | 자동 배정 시각             |
| unassigned_at         | datetime | 학급 이탈 시각, 선택       |
| completed_at          | datetime | 목표를 모두 충족한 시각    |
| rewarded_at           | datetime | 포인트 지급 완료 시각      |
| reward_points_awarded | integer  | 실제 지급액 스냅샷, 기본 0 |
| timestamps            | datetime | 기본                       |

인덱스와 제약:

- mission_id, user_id unique
- user_id, completed_at
- rewarded_at
- reward_points_awarded >= 0 체크 제약

MissionParticipation은 학생별 정확히 한 번 지급을 보장하는 멱등성 경계다.

### 8.3 Mission 상태

#### draft

- 교사만 볼 수 있다.
- 목표, 기간, 보상을 자유롭게 수정할 수 있다.
- 학생 참여 행이 없다.
- 삭제 가능하다.

#### published

- 학생에게 표시된다.
- 발행 시 현재 학급 학생을 자동 배정한다.
- 날짜에 따라 예정, 진행 중, 종료 상태를 파생한다.
- 목표·기간·보상·학급은 잠근다.
- 제목과 설명의 오탈자 수정만 허용할 수 있다.

#### cancelled

- 신규 진행과 보상 판정을 중단한다.
- 이미 지급한 포인트는 회수하지 않는다.
- 학생 화면에는 취소됨으로 표시하거나 기본 목록에서 숨기고 기록에는 남긴다.

#### archived

- 종료된 미션을 교사가 정리한 상태다.
- 학생의 완료 기록과 보상 이력은 유지한다.
- 수정·삭제하지 않는다.

날짜 상태는 DB enum으로 중복 저장하지 않고 메서드로 계산한다.

- scheduled?: Date.current < start_date
- active?: start_date <= Date.current <= end_date
- ended?: Date.current > end_date

### 8.4 교사 생성 흐름

교사 화면:

1. 미션 제목과 설명 입력
2. 담당 학급 선택
3. 시작일과 종료일 입력
4. 목표 추가
5. 목표 수량 입력
6. 보상 포인트 입력
7. 임시 저장 또는 발행

예시:

    제목: 7월 우리 반 독서왕
    기간: 2026-07-20 ~ 2026-07-31
    목표 1: 승인 독후감 3편
    목표 2: 독서 게임 2회
    완료 보상: 100P

발행 전 확인 화면에서 학생에게 보이는 문구와 보상 중복 정책을 보여준다.

### 8.5 유효성 검증

Mission:

- title 필수, 최대 80자
- classroom 필수
- created_by는 해당 학급을 담당하는 교사 또는 허용된 관리자
- start_date와 end_date 필수
- end_date >= start_date
- reward_points는 서버 허용 범위 안
- 발행 시 목표가 하나 이상
- 발행 시 각 목표가 유효

MissionGoal:

- goal_type 허용 목록
- target_count 1 이상
- 같은 mission 안에서 goal_type 유일

보상 상한:

- 기본 권장 범위는 1P 이상 200P 이하
- 상한을 AppSetting의 mission_reward_max_points로 관리하되 설정이 없거나 잘못되면 200을 사용한다.
- 클라이언트 입력 제한만 믿지 않고 모델 또는 도메인 서비스에서 다시 검증한다.

목표 수량의 초기 권장 상한:

- 승인 독후감 1~20편
- 게임 완료 1~50회

긴 방학 미션이 필요하면 상한을 설정으로 조정하되 일반 학기 미션의 과도한 목표를 방지한다.

### 8.6 학생 자동 배정

발행 시 Missions::AssignmentSync 서비스를 호출한다.

동작:

1. mission.classroom의 현재 student 사용자를 조회
2. mission_participations를 insert_all 또는 find_or_create_by로 생성
3. assigned_at 기록
4. 이미 있는 행은 변경하지 않음

새 학생이 학급에 들어오는 경우:

- 교사 학생 생성 경로
- 관리자 사용자 학급 변경 경로
- 기타 학급 배정 경로

위 경로에서 AssignmentSync.for_user를 호출해 현재 진행 중인 published 미션에 배정한다.

안전망:

- 학생 홈 조회 시 현재 학급의 활성 미션 배정을 가볍게 동기화할 수 있다.
- 활동 평가 서비스도 참여 행이 없으면 현재 학급과 기간을 검증한 뒤 생성할 수 있다.

학급을 떠난 경우:

- 기존 participation의 unassigned_at을 기록한다.
- 기존 완료·보상 기록은 보존한다.
- 미완료 미션의 이후 활동은 집계하지 않는다.

게임 원장은 학급 스냅샷이 없으므로 참여 기간을 이용해 전학 전후 경계를 제한한다.

### 8.7 기간과 활동 인정 규칙

모든 날짜 의미는 Asia/Seoul을 기준으로 한다.

#### 승인 독후감 목표

인정 조건:

- report.user_id가 참여 학생
- report.classroom_id가 mission.classroom_id
- report.reviewed = true
- report.revision_of_id가 nil
- report.created_at의 한국 날짜가 start_date 이상 end_date 이하
- 참여 가능 기간 안에 제출

교사가 종료일 이후 승인해도 제출일이 기간 안이면 인정한다.

고쳐쓰기는 별도 독후감 편수로 세지 않는다. 향후 고쳐쓰기 목표를 별도 goal_type으로 추가한다.

같은 책에 여러 원본 독후감을 쓴 경우는 현재 목표 문구가 독후감 편수이므로 각각 센다. 서로 다른 책 수를 원하면 후속 goal_type distinct_books를 만든다.

#### 게임 목표

인정 조건:

- game_play.user_id가 참여 학생
- played_on이 start_date 이상 end_date 이하
- 참여 가능 기간 안의 기록
- 기존 GamePlay 유일 인덱스를 통과한 서버 권위 완료 기록

현재 GamePlay는 같은 학생·게임·책·날짜 조합을 중복 기록하지 않으므로 같은 날 같은 책으로 같은 게임을 반복 제출해도 한 번만 센다.

#### 기간 끝 경계

- 시작일 00:00:00부터 종료일 23:59:59.999...까지 포함한다.
- DB 쿼리는 Time.zone.local로 UTC 범위를 만든다.
- Date.today 대신 Date.current와 Time.current를 사용한다.
- 테스트에서 Time.use_zone('Asia/Seoul')과 travel_to를 사용한다.

### 8.8 진행도 계산

Missions::ProgressCalculator를 만든다.

입력:

- mission
- user 또는 participation

출력 예:

    {
      completed: false,
      goals: [
        { type: 'approved_reports', current: 2, target: 3, met: false },
        { type: 'game_plays', current: 2, target: 2, met: true }
      ]
    }

원칙:

- 모든 목표가 met일 때만 completed=true
- current는 화면에서 target을 넘겨 표시할 필요가 없으면 clamp할 수 있지만 실제 값도 별도로 유지 가능
- 진행 카운터를 MissionParticipation에 중복 저장하지 않는다.
- 목록 화면의 N+1을 막기 위해 여러 학생 또는 여러 미션을 한 번에 집계하는 batch API를 제공한다.

교사 현황 화면은 학생별로 ProgressCalculator를 반복 호출해 개별 COUNT 쿼리를 내지 않아야 한다. mission 한 개에 대해 reports와 game_plays를 user_id로 GROUP BY하여 한 번에 집계한다.

### 8.9 완료와 포인트 지급

Missions::EvaluateProgress 서비스를 만든다.

트리거:

- 독후감 교사 승인 직후
- 게임 완료 GamePlay 신규 기록 직후
- 미션 발행 또는 목표 수정이 가능한 단계의 최종 발행 직후
- 데이터 마이그레이션 또는 관리용 재평가 태스크

처리 순서:

1. 해당 활동 날짜와 학생의 participation에 관련된 published 미션 후보 조회
2. 각 미션의 전체 목표 진행도 재계산
3. 미완료면 종료
4. 완료면 participation 행 잠금
5. 잠금 안에서 completed_at과 보상 상태 재확인
6. 보상 포인트 스냅샷 기록
7. User#award_points로 포인트 지급
8. rewarded_at 기록
9. 커밋 후 학생 화면과 랭킹 갱신

#### 정확히 한 번 지급

필수 안전장치:

- mission_id, user_id unique index
- participation.with_lock 또는 SELECT FOR UPDATE에 해당하는 잠금
- rewarded_at가 있으면 즉시 반환
- 완료 기록과 포인트 지급을 하나의 DB 트랜잭션으로 묶음
- 예외 발생 시 둘 다 롤백
- 동일 승인·게임 요청이 재시도되어도 추가 지급 없음

의사 흐름:

    participation.with_lock do
      return if participation.rewarded_at?
      return unless calculator.completed?

      transaction do
        participation.completed_at ||= Time.current
        participation.reward_points_awarded = mission.reward_points
        user.award_points(mission.reward_points, reason: mission reward key)
        participation.rewarded_at = Time.current
        participation.save!
      end
    end

User#award_points가 트랜잭션 중 방송을 수행하는 현재 구조는 점검해야 한다. 필요하면 DB 변경은 트랜잭션 안에서 처리하고 Turbo·랭킹 방송은 after_commit 이후 수행하도록 포인트 서비스 경계를 정리한다.

#### 기본 활동 포인트와 중복

- 독후감과 게임은 기존 기본 포인트를 받는다.
- 미션을 완료하면 별도 보너스 포인트를 받는다.
- 이는 의도된 중복 보상이다.
- 학생 화면에는 기본 활동 포인트와 미션 보너스를 구분해서 표시한다.

### 8.10 미션 수정·취소·삭제 정책

#### 발행 전

- 모든 필드 수정 가능
- 삭제 가능

#### 발행 후 시작 전

권장안은 목표·기간·보상 변경을 허용하지 않고 발행 취소 후 새 미션을 만들게 하는 것이다. 학생이 이미 내용을 확인했을 수 있기 때문이다.

완화안이 필요하면 시작 전까지만 수정하되:

- 모든 participation을 재동기화
- 학생에게 변경 알림
- 변경 이력 기록

첫 구현은 잠금 정책을 선택한다.

#### 시작 후

- 제목과 설명 오탈자만 수정 가능
- 목표, 목표 수량, 기간, 학급, 보상 수정 불가
- 취소만 가능
- 물리 삭제 불가

#### 보상 지급 후

- 어떤 필드 변경으로도 이미 지급한 포인트를 회수하지 않는다.
- 취소해도 기존 지급 기록을 보존한다.

### 8.11 학생 화면

#### 홈 미션 카드

- 미션 제목
- 남은 기간 또는 종료일
- 목표별 현재/목표
- 전체 진행률
- 완료 보상 포인트
- 완료 시 축하 상태

진행률 계산은 목표별 비율 평균보다 목표 수량 합산이 오해를 만들 수 있으므로, 각 목표를 개별 progress bar로 보여주는 것을 기본으로 한다.

#### 독서활동 미션 영역

- 현재 선택한 활동과 관련된 목표 강조
- 독후감 목표라면 독후감 CTA 옆에 현재/목표 표시
- 게임 목표라면 게임 영역에 현재/목표 표시
- 미션 상세로 이동 가능

#### 내 서재 완료 기록

- 완료한 미션을 활동 타임라인 또는 별도 섹션에 표시
- 완료일과 받은 포인트 표시
- 취소·미완료 미션은 기본 완료 기록에 포함하지 않음

### 8.12 교사 화면

#### 목록

- 임시 저장, 예정, 진행 중, 종료, 취소 상태 필터
- 제목, 학급, 기간, 목표 요약, 보상, 완료 학생 수
- 새 미션 CTA

#### 상세

- 미션 조건
- 전체 학생 수
- 완료·진행 중 학생 수
- 학생별 목표 진행도
- 보상 지급 상태
- CSV가 필요하면 후속으로 추가

#### 권한

- 담임은 teacher_classrooms에 속한 학급의 미션만 생성·조회·수정
- 타 학급 classroom_id 주입은 403
- 학생은 교사 관리 라우트 접근 불가
- superadmin 권한은 현재 Teacher 영역 정책과 일관되게 별도 확인

---

## 9. 기존 미션에서 새 미션으로 데이터 전환

### 9.1 원칙

- 기존 마이그레이션을 수정하지 않는다.
- additive schema → 코드 전환 → 오래된 컬럼 제거 순서로 진행한다.
- 운영 데이터가 있는지 먼저 확인한다.
- 레거시 참여 이력이 몬스터 조건에서 갑자기 사라지지 않게 한다.

### 9.2 권장 전환 단계

#### 1단계: 새 테이블과 컬럼 추가

- missions에 created_by_id, description, reward_points, status, published_at, cancelled_at 추가
- mission_goals 생성
- mission_participations 생성
- 기존 missions.book_id와 reports.mission_id는 임시 유지

#### 2단계: 레거시 데이터 백필

기존 reports.mission_id별로 distinct mission_id, user_id를 추출한다.

각 조합에 대해:

- MissionParticipation 생성
- assigned_at은 mission.start_date 시작 시각 또는 연결 report의 최초 시각
- completed_at은 최초 연결 report 시각
- reward_points_awarded=0
- rewarded_at=completed_at

기존 미션:

- status=archived
- reward_points=0
- 목표가 없어도 archived 상태에서는 유효하도록 함
- created_by_id는 classroom.teacher_id로 가능한 범위에서 백필

이렇게 하면 기존 ReadingStats#missions 의미를 새 완료 participation 수로 옮겨도 누적 몬스터 조건이 보존된다.

#### 3단계: 새 코드로 읽기 전환

- ReadingStats#missions를 rewarded 여부가 아니라 completed_at이 있는 participation distinct count로 변경
- 학생과 교사 미션 화면을 새 모델로 변경
- 새 미션은 MissionGoal과 자동 배정을 사용

#### 4단계: 세션 참여 제거

- MissionsController#join 제거
- join_mission_path 제거
- session[:active_mission_id] 쓰기 제거
- ReportsController#link_participation에서 mission 분기 제거
- challenge 분기는 그대로 유지

#### 5단계: 레거시 컬럼 제거

- reports의 missions FK 제거
- reports.mission_id 컬럼 제거
- missions의 books FK 제거
- missions.book_id 컬럼 제거

### 9.3 운영 데이터가 없는 경우

개발·테스트 데이터만 있고 초기화가 허용되더라도 정식 마이그레이션 경로는 유지한다. 로컬 DB를 재생성하는 방식만 문서에 의존하면 배포 환경과 CI가 검증되지 않는다.

---

## 10. 서비스와 이벤트 연결

### 10.1 권장 클래스

#### StudentHomeQuery

- 추천 도서
- 인기 도서
- 이어하기
- 활성 미션 요약

#### StudentLibraryQuery

- 책별 활동 집계
- 필터·정렬·페이지네이션
- 레거시 독후감 그룹

#### Missions::AssignmentSync

- 발행 시 학급 학생 자동 배정
- 학생 학급 변경 시 참여 기간 갱신

#### Missions::ProgressCalculator

- 목표별 현재값 계산
- 단건 및 batch 집계

#### Missions::EvaluateProgress

- 관련 미션 후보 탐색
- 완료 판정
- Rewarder 호출

#### Missions::Rewarder

- participation 잠금
- 완료·지급 멱등성 보장
- User#award_points 호출

서비스가 너무 잘게 쪼개져 호출 관계가 불명확해지면 EvaluateProgress가 Calculator와 Rewarder를 조정하는 단일 진입점이 되도록 한다.

### 10.2 이벤트 연결 지점

#### 독후감

Teacher::ReviewsController#finalize_approval에서:

1. reviewed와 reviewed_at 저장
2. 기존 뱃지·진화·몬스터 해금 재평가
3. Missions::EvaluateProgress 호출
4. 미션 완료 메시지를 교사와 학생에게 전달

동일 독후감 재승인은 기존 정책으로 막고, 미션 Rewarder도 별도로 멱등해야 한다.

#### 게임

GamePlay가 실제로 신규 생성된 경우에만:

1. 기존 게임 포인트 지급
2. 기존 몬스터 해금 재평가
3. Missions::EvaluateProgress 호출

유일 인덱스 충돌 또는 중복 재제출로 새 GamePlay가 생기지 않으면 미션 진행도도 증가하지 않는다.

#### 학생 학급 변경

- 이전 학급 미션 participation의 unassigned_at 기록
- 새 학급의 현재 published 미션 자동 배정
- 이미 완료한 이전 미션 기록은 보존

#### 미션 발행

- transaction 안에서 status를 published로 전환
- 목표와 보상 검증
- 발행 후 AssignmentSync 실행
- 발행 실패 시 일부 참여 행만 남지 않게 처리

---

## 11. 쿼리와 성능

### 11.1 홈

- 추천 도서는 limit을 명시한다.
- 인기 도서는 기간과 학급·학교 범위를 제한한다.
- N+1 방지를 위해 cover 등 Book 필드는 한 번에 조회한다.
- 홈의 각 섹션은 최대 5~10개만 렌더한다.

### 11.2 내 서재

전체 활동을 Ruby에서 group_by하지 않는다.

권장 접근:

- reports를 book_id로 집계한 서브쿼리
- game_plays를 book_id로 집계한 서브쿼리
- Book 목록과 결합
- last_activity_at으로 정렬
- 필요한 페이지의 Book만 로드

SQLite와 테스트 호환성을 우선하고 DB별 전용 문법은 피한다. UNION과 복잡한 조인이 유지보수를 크게 어렵게 하면 두 집계 쿼리의 제한된 결과를 병합하는 query object를 사용하되 사용자 전체 활동을 무제한 로드하지 않는다.

권장 인덱스 점검:

- reports(user_id, book_id, created_at)
- reports(user_id, reviewed, created_at)
- game_plays(user_id, book_id, played_on)

현재 인덱스와 중복되지 않는지 schema를 확인한 후 추가한다.

### 11.3 미션 진행도

학생 홈:

- 현재 학생 한 명의 활성 미션만 계산하므로 단건 쿼리 허용

교사 상세:

- reports를 user_id로 GROUP BY
- game_plays를 user_id로 GROUP BY
- participation과 학생을 includes
- 학생 수 × 목표 수만큼 COUNT 쿼리를 반복하지 않음

후속 캐시가 필요하면 계산 결과를 영속 카운터로 바로 바꾸지 말고 짧은 캐시부터 검토한다. 원장과 캐시 불일치 시 원장이 단일 진실이다.

---

## 12. 인가·보안·정합성

### 12.1 학생 경계

- library는 Current.user의 Report와 GamePlay만 조회
- reading_activity의 book_id는 Book 존재 여부만 결정하며 개인 활동 조회는 Current.user로 다시 스코프
- mission participation은 user_id와 classroom 소속을 서버가 결정
- 클라이언트가 mission_id, user_id, current_count, completed 값을 제출하지 않음

### 12.2 교사 경계

- 생성 시 classroom_id를 owned_classroom!으로 검증
- update에서 classroom_id 재배정 금지
- mission 상세의 participation도 mission classroom 학생으로 제한
- reward_points와 target_count는 strong parameters 후 모델 검증

### 12.3 포인트 정합성

- 클라이언트는 완료나 지급을 직접 호출할 수 없음
- 서버 권위 Report 승인과 GamePlay 생성만 진행 트리거
- reward_points는 Mission의 발행 시 값을 사용
- 실제 지급액을 participation에 스냅샷으로 보존
- unique index와 row lock으로 동시 지급 방지
- 실패 재시도 시 추가 지급 없음

### 12.4 삭제 정합성

- 보상이 발생한 published 미션은 물리 삭제 금지
- 학생 삭제 시 participation 처리 정책은 User dependent 관계와 개인정보 정책에 맞춤
- Mission 삭제는 draft에만 허용
- FK on_delete 정책을 명시하고 Rails dependent 옵션과 일치시킴

---

## 13. UI·콘텐츠·디자인 기준

### 13.1 학생 언어

기술 용어 대신 행동과 상태를 말한다.

- published → 시작 예정 또는 진행 중
- approved_reports → 선생님이 확인한 독후감
- game_plays → 완료한 독서 게임
- rewarded → 보상 받음

### 13.2 진행도

- 각 목표를 별도 행으로 표시
- 현재값/목표값을 텍스트로 병기
- progress 요소 또는 aria-valuenow를 가진 접근 가능한 진행 표시 사용
- 완료 여부를 색상과 체크 아이콘·문구로 함께 표시

### 13.3 보상 피드백

완료 시:

- 미션 이름
- 달성 목표
- 받은 포인트
- 새 총 포인트
- 몬스터 발견 또는 진화 가능 여부

상점 제거 후 포인트 사용처를 오해하지 않도록 포인트 안내는 레벨·진화·랭킹과 연결해 설명한다.

### 13.4 빈 상태

- 홈 추천 없음: 책 검색하기
- 내 서재 기록 없음: 첫 독서활동 시작하기
- 진행 미션 없음: 현재 진행 중인 우리 반 미션이 없어요
- 책 선택 없음: 먼저 읽은 책을 골라 주세요

빈 상태는 dead end가 되지 않도록 한 개의 명확한 CTA를 제공한다.

---

## 14. 구현 단계

각 단계는 가능한 한 독립 배포와 회귀 검증이 가능해야 한다.

### Phase 0. 기준선과 의사결정 고정

- 현재 전체 테스트 통과 여부 기록
- 현재 routes 출력 저장
- 운영 DB에 Mission, reports.mission_id, ShopItem, Purchase 데이터가 있는지 확인
- 운영 데이터 백업 정책 확정
- 미션 보상 상한 기본값 확정
- 발행 후 수정 잠금 정책 확정
- 레거시 미션 백필 정책 확정

완료 기준:

- 데이터 보존 여부가 문서화됨
- 실패 중인 기존 테스트가 새 변경과 구분됨

### Phase 1. 미션 additive 스키마

- missions 새 컬럼 추가
- mission_goals 생성
- mission_participations 생성
- 모델·연관·검증 추가
- 레거시 백필용 데이터 마이그레이션 또는 rake task 작성
- 기존 미션 기능은 아직 유지

예상 파일:

- db/migrate/*
- app/models/mission.rb
- app/models/mission_goal.rb
- app/models/mission_participation.rb
- app/models/user.rb
- app/models/classroom.rb
- app/models/CLAUDE.md
- db/CLAUDE.md
- test/models/*

완료 기준:

- 새 스키마가 기존 데이터에 additive하게 적용됨
- unique와 check 제약이 테스트됨
- 레거시 화면이 아직 깨지지 않음

### Phase 2. 미션 도메인 서비스

- AssignmentSync 구현
- ProgressCalculator 단건·batch 구현
- EvaluateProgress 구현
- Rewarder 구현
- report 승인 이벤트 연결
- GamePlay 신규 기록 이벤트 연결
- ReadingStats#missions 전환
- 몬스터 조건 회귀 테스트

예상 파일:

- app/services/missions/*
- app/services/reading_stats.rb
- app/controllers/teacher/reviews_controller.rb
- app/controllers/games/attempts_controller.rb
- app/controllers/games/book_controller.rb
- app/models/concerns/pointable.rb 또는 보상 서비스
- app/services/CLAUDE.md
- test/services/missions/*
- test/integration/mission_progress_test.rb
- test/integration/mission_reward_test.rb

완료 기준:

- 독후감과 게임 목표가 기간 안에서만 집계됨
- 복수 목표 AND 판정
- 보상 한 번 지급
- 동시 또는 반복 호출에서도 중복 지급 없음
- 완료 미션 수가 몬스터 조건에 반영됨

### Phase 3. 교사 미션 UI 교체

- 미션 draft 생성 폼
- 동적 목표 입력
- 발행 액션
- 상태별 목록
- 학생별 진행 현황
- 취소·보관 정책
- 교사 소유 학급 인가

예상 파일:

- config/routes.rb
- app/controllers/teacher/missions_controller.rb
- app/views/teacher/missions/*
- app/policies/mission_policy.rb 또는 교사 전용 정책
- app/javascript/controllers/mission_goals_controller.js
- app/controllers/teacher/CLAUDE.md
- app/views/CLAUDE.md
- app/javascript/CLAUDE.md
- test/integration/teacher_missions_test.rb

완료 기준:

- 교사가 기간·목표·보상을 설정해 발행 가능
- 타 학급 접근 차단
- 시작 후 보호 필드 수정 차단
- 진행 현황에 N+1 없음

### Phase 4. 학생 홈·내 서재·독서활동

- student nav 5개로 변경
- 학생 대시보드를 홈으로 개편
- LibrariesController와 내 서재 화면 추가
- ReadingActivitiesController와 활동 허브 추가
- 홈 추천·인기·이어하기 쿼리 추가
- 홈과 독서활동에 미션 카드 추가
- reports와 games 기존 진입점을 새 흐름에 연결

예상 파일:

- config/routes.rb
- app/views/shared/_student_nav.html.erb
- app/controllers/dashboard_controller.rb
- app/views/dashboard/student.html.erb
- app/controllers/libraries_controller.rb
- app/views/libraries/show.html.erb
- app/controllers/reading_activities_controller.rb
- app/views/reading_activities/show.html.erb
- app/services/student_home_query.rb
- app/services/student_library_query.rb
- app/views/reports/*
- app/views/games/catalog/*
- 관련 CLAUDE.md
- test/integration/student_navigation_test.rb
- test/integration/student_home_test.rb
- test/integration/student_library_test.rb
- test/integration/reading_activity_test.rb

완료 기준:

- 학생 메뉴가 정확히 5개
- 홈, 내 서재, 독서활동의 중복 책임이 없음
- 책 선택 후 독후감과 모든 게임으로 진입 가능
- 책별 Report와 GamePlay 기록이 내 서재에 표시
- 진행 중 미션이 홈에 자동 표시

### Phase 5. 기존 미션 참여 방식 제거

- join 액션과 버튼 삭제
- active_mission_id 세션 제거
- reports.mission_id 쓰기 제거
- 레거시 참여 데이터 백필 검증
- reports.mission_id와 missions.book_id 컬럼 제거
- 기존 mission_participation_test를 새 자동 진행 테스트로 교체

Challenge의 active_challenge_id와 reports.challenge_id는 이번 범위에서 유지한다.

완료 기준:

- 코드 전체에서 active_mission_id 참조 0건
- 코드 전체에서 reports.mission_id 런타임 참조 0건
- 새 완료 미션 수와 백필된 레거시 완료 수가 예상과 일치

### Phase 6. 상점 제거

- 학생·관리자 nav에서 상점 제거
- 상점·구매 라우트 제거
- 컨트롤러·뷰·모델·정책·헬퍼 삭제
- 먹이주기 제거
- 시드·테스트·문서 제거
- DB 테이블과 care 컬럼 제거

완료 기준:

- ShopItem, Purchase 상수 참조 0건
- shop_path, purchases_path, admin_shop_items_path 참조 0건
- feed_monster_path 참조 0건
- 학생 화면에 상점·먹이 구매 안내 없음
- 포인트·진화·랭킹 테스트 정상

### Phase 7. 문서·운영·최종 정리

- 역할별 매뉴얼 갱신
- 모든 관련 CLAUDE.md 갱신
- README 현재 기능표 갱신
- DESIGN의 현재 정보 구조 갱신
- 과거 문서에 superseded 안내 추가
- 운영 데이터 마이그레이션 결과 기록
- 전체 품질 검사

완료 기준:

- 문서 검색에서 상점이 현재 기능처럼 설명되지 않음
- 미션 매뉴얼이 실제 동작과 일치
- 신규 구현과 테스트 명칭이 새 메뉴 용어와 일치

---

## 15. 테스트 계획

### 15.1 모델 테스트

Mission:

- 제목 필수
- 시작일·종료일 필수
- 종료일이 시작일보다 빠르면 실패
- 보상 최소·최대 검증
- 발행 시 목표 필수
- 발행 후 보호 필드 수정 차단

MissionGoal:

- 허용 goal_type
- target_count 양수
- mission 안 goal_type 중복 차단

MissionParticipation:

- mission/user 유일
- 학생만 참여 가능
- 음수 reward_points_awarded 차단

### 15.2 서비스 테스트

ProgressCalculator:

- 승인 전 독후감 미집계
- 승인 후 집계
- 고쳐쓰기 미집계
- 기간 전·후 독후감 미집계
- 종료 후 승인된 기간 내 제출 독후감 집계
- GamePlay 기간 경계
- 동일 일일 중복 게임 미집계
- 복수 목표 AND
- current가 target을 넘는 경우
- 학급 이탈 이후 활동 미집계

AssignmentSync:

- 발행 시 학급 학생 전원 배정
- 타 학급 학생 미배정
- 반복 호출 멱등
- 새 학생 중도 배정
- 전학 시 unassigned_at

Rewarder:

- 완료 전 지급 없음
- 완료 시 정확한 포인트
- 반복 호출 추가 지급 없음
- 동시 호출 한 번 지급
- 실패 시 participation과 points 함께 롤백
- 지급 후 랭킹·뱃지·진화 후크

### 15.3 통합 테스트

교사:

- 담당 학급 미션 생성·발행
- 두 목표 입력
- 잘못된 기간 거부
- 과도한 보상 거부
- 타 학급 주입 403
- 학생별 진행도 조회
- 시작 후 보호 필드 수정 거부
- 취소 후 신규 보상 없음

학생:

- 5개 메뉴가 모든 학생 주요 화면에 일관되게 렌더
- 홈 추천 도서와 폴백
- 내 서재 책별 독후감·게임 집계
- 레거시 book_title 독후감 표시
- 독서활동 책 선택
- 선택 책을 독후감 폼에 전달
- 선택 책을 5종 게임 경로에 전달
- 홈 미션 진행도
- 미션 완료 축하와 포인트

상점 제거:

- 삭제된 라우트가 더 이상 생성되지 않음
- 도감 상세에 먹이 UI 없음
- 관리자 nav에 상점 없음
- 몬스터 진화 포인트 차감은 유지

### 15.4 회귀 테스트

- 독후감 AI 첨삭과 포인트
- 교사 승인
- 게임 채점과 멱등 포인트
- GamePlay 기록
- 몬스터 발견·진화
- 랭킹 방송
- 학생 로그인과 역할별 대시보드
- Challenge 기존 참여 흐름
- Pundit verify_authorized

### 15.5 품질 명령

프로젝트의 실제 bin 스크립트와 CI 설정을 확인한 뒤 다음을 실행한다.

- 전체 Minitest
- 관련 테스트 파일 단독 실행
- RuboCop
- Brakeman
- Tailwind CSS 빌드 또는 클래스 emit 확인
- bin/rails routes 점검
- db:migrate와 rollback 가능 범위 점검
- 새 DB에서 db:setup 또는 db:prepare

대규모 삭제 후에는 rg로 금지된 잔여 참조를 확인한다.

- ShopItem
- Purchase
- shop_path
- purchases_path
- admin_shop_items
- feed_monster
- active_mission_id
- join_mission
- reports.mission_id

역사 문서의 단어까지 무조건 0건을 요구하지 않고 런타임 코드·테스트·현재 매뉴얼에서 0건인지 구분한다.

---

## 16. 데이터 마이그레이션 체크리스트

배포 전:

- Mission.count
- Mission.where.not(book_id: nil).count
- Report.where.not(mission_id: nil).count
- distinct mission_id/user_id 참여 조합 수
- ShopItem.count
- Purchase.count
- UserMonster.where.not(care: nil).count

백필 후:

- 레거시 distinct 참여 조합 수와 생성된 MissionParticipation 수 비교
- 중복 participation 0건
- completed_at 누락 0건
- 레거시 participation의 reward_points_awarded=0 확인
- 사용자별 이전 ReadingStats.missions와 새 완료 미션 수 비교

상점 삭제 전:

- 운영 백업 시각 기록
- 구매 데이터 보존 여부 기록
- 현재 포인트 잔액 스냅샷 필요 여부 결정

삭제 후:

- schema에서 purchases와 shop_items 없음
- user_monsters.care 제거 여부 확인
- foreign key 잔여 없음
- db:prepare 새 환경 성공

---

## 17. 관측성과 운영

### 로그

미션 보상 시 구조화 가능한 정보를 남긴다.

- mission_id
- user_id
- participation_id
- reward_points
- completed_at
- rewarded_at
- trigger_type
- trigger_id

학생 이름이나 독후감 본문은 로그에 남기지 않는다.

### 관리용 점검

초기 배포 동안 다음 불일치를 점검할 수 있는 rake task를 권장한다.

- completed_at은 있으나 rewarded_at이 없는 participation
- rewarded_at은 있으나 reward_points_awarded가 0인 신규 미션
- 목표를 충족했으나 completed_at이 없는 participation
- classroom이 맞지 않는 participation

자동 복구 태스크는 먼저 dry-run을 기본으로 하고 명시 옵션이 있을 때만 변경한다.

### 지표

- 발행 미션 수
- 미션별 배정 학생 수
- 완료율
- 평균 완료 소요일
- 지급 포인트 총량
- 학생별 미션 보상 비중

이 지표는 교사별 과도한 보상이 랭킹에 영향을 주는지 판단하는 데 사용한다.

---

## 18. 위험과 대응

| 위험                  | 영향                | 대응                                 |
| --------------------- | ------------------- | ------------------------------------ |
| 발행 후 목표 변경     | 학생별 조건 불공정  | 발행 후 보호 필드 잠금               |
| 보상 동시 지급        | 포인트 중복         | unique index, row lock, transaction  |
| 종료 후 독후감 승인   | 정당한 활동 누락    | 제출일 기준 집계, 승인 이벤트 재평가 |
| 전학 학생 게임 집계   | 다른 학급 활동 혼입 | participation 배정·이탈 기간 적용    |
| 내 서재 집계 N+1      | 느린 목록           | GROUP BY batch query와 페이지네이션  |
| 추천 쿼리 과부하      | 홈 느려짐           | 제한된 기간·수량, 폴백, 필요 시 캐시 |
| 상점 테이블 조기 삭제 | 구버전 코드 장애    | 두 단계 배포                         |
| 레거시 미션 기록 소실 | 몬스터 조건 퇴행    | participation 0P 완료 백필           |
| 포인트 보상 편차      | 랭킹 왜곡           | 서버 상한과 운영 지표                |
| 책 미연결 독후감      | 내 서재 누락        | 레거시 그룹 표시와 데이터 보정       |

---

## 19. 최종 완료 기준

기능:

- 학생 상위 메뉴가 홈, 내 서재, 독서활동, 도감, 랭킹 5개다.
- 홈에서 추천 도서, 이어하기, 진행 중 미션을 볼 수 있다.
- 내 서재에서 책별 독후감과 게임 활동을 볼 수 있다.
- 독서활동에서 책을 고른 뒤 독후감 또는 게임을 시작할 수 있다.
- 도감과 랭킹이 새 포인트 흐름에서 정상 동작한다.
- 상점·구매·먹이주기가 UI와 런타임 코드·DB에서 제거됐다.
- 교사가 기간·복수 목표·보상 포인트가 있는 미션을 발행할 수 있다.
- 학생은 자동 배정되고 진행도가 자동 반영된다.
- 모든 목표 달성 시 포인트가 정확히 한 번 지급된다.

정합성:

- 기간 밖 활동은 집계되지 않는다.
- 기간 내 제출 후 늦게 승인된 독후감은 집계된다.
- 미션 완료 수가 몬스터 조건에 반영된다.
- 학급 경계와 역할 인가 테스트가 통과한다.
- 레거시 미션 이력이 보존된다.

품질:

- 전체 테스트 통과
- RuboCop 통과
- Brakeman 신규 경고 없음
- 새 DB setup과 기존 DB migrate 모두 성공
- 관련 CLAUDE.md와 사용자 매뉴얼 갱신
- 현재 기능 문서에서 상점이 제거되고 새 메뉴·미션 설명이 일치

---

## 20. 구현 시 기본값으로 확정할 항목

추가 논의가 없다면 다음 값을 구현 기본안으로 사용한다.

- 학생 메뉴: 홈 / 내 서재 / 독서활동 / 도감 / 랭킹
- 미션 참여: 학급 학생 자동 배정
- 목표 조합: 모두 충족해야 완료
- 초기 목표 종류: 승인된 원본 독후감 수, GamePlay 완료 수
- 활동 기간: 시작일과 종료일 모두 포함, Asia/Seoul
- 독후감 인정: 기간 내 제출 + 교사 승인
- 고쳐쓰기: 독후감 편수에서 제외
- 게임 인정: 신규 GamePlay 원장 행
- 보상: 기본 활동 포인트와 별도 중복 지급
- 보상 상한: 기본 200P
- 보상 회수: 하지 않음
- 발행 후 목표·기간·보상 변경: 금지
- 완료 미션 수: MissionParticipation.completed_at 기준
- 내 서재: 별도 찜 모델 없이 실제 활동 기록 기준
- 상점: 메뉴 숨김이 아닌 전체 코드·테이블 제거
- 포인트: 유지
- 몬스터 먹이주기와 care 데이터: 제거
- Challenge: 이번 범위에서 유지

이 기본값 중 하나를 바꾸면 데이터 모델, 테스트, 학생 안내 문구에 미치는 영향을 먼저 이 문서에 반영한다.
