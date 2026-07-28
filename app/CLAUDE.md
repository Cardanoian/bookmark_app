# app/ — 애플리케이션 코드 허브 (Rails 8.1 MVC + 서비스·정책·잡·프런트)

독서교육 플랫폼 '책갈피'의 모든 런타임 코드가 모이는 최상위 계층입니다. 표준 Rails MVC(컨트롤러·모델·뷰)에 더해, 도메인 로직을 담는 서비스 객체(`services/`), Pundit 기반 인가(`policies/`), 백그라운드 잡(`jobs/`), Hotwire 프런트엔드(`javascript/`)로 관심사를 분리합니다. 총괄관리자·학교관리자·사서·교사·학생 5개 역할이 각자의 네임스페이스와 대시보드를 가지며, 컨트롤러·뷰·정책이 역할별로 나뉘어 있습니다.

## 하위 폴더
- [`controllers/`](controllers/CLAUDE.md) — 요청 처리. 루트 리소스 컨트롤러 + 역할별 네임스페이스(`admin/`·`teacher/`·`librarian/`·`school_admin/`·`games/`)
- [`models/`](models/CLAUDE.md) — ActiveRecord 도메인 모델 + 재사용 로직 `concerns/`(leveling·pointable·evolvable 등)
- [`services/`](services/CLAUDE.md) — 도메인 서비스 객체(랭킹·독서통계·몬스터) + AI 연동 `ai/`(Claude·OCR·독후감 첨삭)
- [`policies/`](policies/CLAUDE.md) — Pundit 인가 정책. 리소스별 접근 권한 규칙
- [`views/`](views/CLAUDE.md) — ERB 뷰. 리소스별 화면 + 역할별 레이아웃 + turbo_stream 응답
- [`javascript/`](javascript/CLAUDE.md) — Stimulus 컨트롤러(Import Maps). 검색 자동완성·사진 압축·도감 등 클라이언트 UI
- [`jobs/`](jobs/CLAUDE.md) — Active Job 백그라운드 작업(AI 첨삭·OCR 비동기 처리)
- [`helpers/`](helpers/CLAUDE.md) — 뷰 헬퍼. 표시 포맷·아이콘·상태 배지 등 뷰 보조 로직

## 파일 / 하위 리소스
- [`mailers/`](mailers/CLAUDE.md) — 트랜잭셔널 메일(Resend). 교직원 비밀번호 재설정·교사 가입 이메일 인증
- `assets/` — 정적 자산. `tailwind/application.css`(Tailwind v4 진입점 — `@import "tailwindcss"` + **`@theme` 디자인 토큰**[DESIGN.md 색·폰트·라운드 1:1 매핑, 기본 팔레트는 유지] + **전역 base**[Pretendard 폰트 스택·포커스 링·본문 배경·`prefers-reduced-motion`·**데스크톱 루트 폰트 확대**(`screen` 한정 2단계 — `min-width:1024px`→`106.25%`(17px), `min-width:1280px`→`112.5%`(18px), <1024px 는 16px 유지. rem 기반이라 글자·간격·아이콘·터치 영역이 통째로 비례 확대되며, 미디어쿼리 길이가 루트 폰트와 무관해 lg 구간만 실효 공간이 좁아지므로 2단계로 완만하게 올린다. 초등 전학년 대상 가독성 대응이며 **뷰별 `text-xs sm:text-base` 분기 대신 여기 한 곳에서만 조절**한다. 이 확대에 폭이 딸려 넓어지지 않도록 `--shell-max-*` 셸 토큰과 레이아웃 `max-w-[1536px]`는 rem 이 아닌 **px 고정**)] + **`@layer components` 공통 클래스**[`.btn*`·`.card*`·`.form-*`·`.badge*`·`.page-shell*`·`.app-header*`·`.app-wordmark`·`.progress-bar`·`.state-banner*`](`.page-title`/`.page-header`는 브랜드 악센트·하단 헤어라인으로 강조))를 `bin/rails tailwindcss:build`로 `builds/tailwind.css` 생성. `stylesheets/application.css`는 Propshaft 가 직접 서빙하는 순수 CSS로 **Pretendard `@font-face`**(자체호스팅)를 둔다. `fonts/pretendard/PretendardVariable.woff2`(가변, self-host — `config/initializers/assets.rb`가 `app/assets/fonts`를 asset path 에 추가). `stylesheet_link_tag :app`은 `stylesheets/application.css` + `builds/tailwind.css` 둘 다 링크. 전역 브랜드 헤더 밴드(`app-header`)는 `layouts/application`·`admin` 최상단에 렌더된다. `images/ui-icons.svg`는 전 화면 공용 symbol 스프라이트, `images/empty_states/`는 128×128 투명 PNG 빈 화면 일러스트이며, `images/monsters/`에는 기본 표시용 256×256 정적 PNG 72종과 상세 상단용 애니메이션 WebP 72종이 있다(별도 CLAUDE.md 없음).

## 패턴·규칙
- 프런트엔드는 Hotwire(Turbo + Stimulus) + Import Maps + Propshaft + Tailwind CSS 구성. 번들러·Node 빌드 없음.
- 컨트롤러는 얇게 유지하고 도메인 로직은 `services/`로 위임. 인가는 컨트롤러가 아닌 `policies/`에서 판단.
- 무거운 외부 연동(AI 첨삭·OCR)은 컨트롤러에서 직접 호출하지 않고 `jobs/`로 비동기 처리.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
