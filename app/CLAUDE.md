# app/ — 애플리케이션 코드 허브 (Rails 8.1 MVC + 서비스·정책·잡·프런트)

독서교육 플랫폼 '책갈피'의 모든 런타임 코드가 모이는 최상위 계층입니다. 표준 Rails MVC(컨트롤러·모델·뷰)에 더해, 도메인 로직을 담는 서비스 객체(`services/`), Pundit 기반 인가(`policies/`), 백그라운드 잡(`jobs/`), Hotwire 프런트엔드(`javascript/`)로 관심사를 분리합니다. 총괄관리자·학교관리자·사서·교사·학생 5개 역할이 각자의 네임스페이스와 대시보드를 가지며, 컨트롤러·뷰·정책이 역할별로 나뉘어 있습니다.

## 하위 폴더
- [`controllers/`](controllers/CLAUDE.md) — 요청 처리. 루트 리소스 컨트롤러 + 역할별 네임스페이스(`admin/`·`teacher/`·`librarian/`·`school_admin/`·`games/`)
- [`models/`](models/CLAUDE.md) — ActiveRecord 도메인 모델 + 재사용 로직 `concerns/`(leveling·pointable·evolvable 등)
- [`services/`](services/CLAUDE.md) — 도메인 서비스 객체(랭킹·독서통계·몬스터) + AI 연동 `ai/`(Gemini·OCR·독후감 첨삭)
- [`policies/`](policies/CLAUDE.md) — Pundit 인가 정책. 리소스별 접근 권한 규칙
- [`views/`](views/CLAUDE.md) — ERB 뷰. 리소스별 화면 + 역할별 레이아웃 + turbo_stream 응답
- [`javascript/`](javascript/CLAUDE.md) — Stimulus 컨트롤러(Import Maps). 검색 자동완성·사진 압축·원고지·도감 등 클라이언트 UI
- [`jobs/`](jobs/CLAUDE.md) — Active Job 백그라운드 작업(AI 첨삭·OCR 비동기 처리)
- [`helpers/`](helpers/CLAUDE.md) — 뷰 헬퍼. 표시 포맷·아이콘·상태 배지 등 뷰 보조 로직

## 파일 / 하위 리소스
- `mailers/` — `application_mailer.rb` 하나. 앱 메일러의 공통 기반 클래스(별도 CLAUDE.md 없음)
- `assets/` — 정적 자산. `tailwind/application.css`(Tailwind 진입점, `@import "tailwindcss"`)를 빌드해 `builds/tailwind.css` 생성. `images/monsters/`에는 `image_key`로 참조하는 애니메이션 WebP 72종이 있으며 `monsters:install_assets`로 재설치한다(별도 CLAUDE.md 없음).

## 패턴·규칙
- 프런트엔드는 Hotwire(Turbo + Stimulus) + Import Maps + Propshaft + Tailwind CSS 구성. 번들러·Node 빌드 없음.
- 컨트롤러는 얇게 유지하고 도메인 로직은 `services/`로 위임. 인가는 컨트롤러가 아닌 `policies/`에서 판단.
- 무거운 외부 연동(AI 첨삭·OCR)은 컨트롤러에서 직접 호출하지 않고 `jobs/`로 비동기 처리.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
