# 책갈피 (Chaekgalpi / bookmark_app) — 프로젝트 루트

초등학교 전학년을 위한 **AI 독후감 첨삭 + 반려 몬스터 게이미피케이션** 독서 교육 플랫폼입니다.
Ruby on Rails 8.1 모놀리식 앱이며, 학생·담임교사·교무관리자·사서·총괄관리자 **5개 역할**을 하나의 앱으로 지원합니다.

핵심 가치는 ① Gemini 기반 **AI 5축 발전적 첨삭**(내용·감상·삶·구성·맞춤법), ② **24라인 72폼 반려 몬스터 도감·진화**, ③ 학교 현장 운영(검토·통계·도서관·관리자)입니다.
외부 API(Gemini·네이버 도서검색·정보나루)는 **키가 없어도 폴백으로 완전 동작**하도록 설계되어 있습니다.

## 기술 스택 (요약)
- **프레임워크/언어**: Rails 8.1 · Ruby 4.0.5
- **DB**: SQLite 다중 DB (primary/cache/queue/cable) + Solid Queue·Cache·Cable
- **프런트**: Hotwire(Turbo·Stimulus) · Import Maps · Propshaft · Tailwind CSS
- **인가/인증**: Pundit(역할·학교 경계 격리) · `has_secure_password`(bcrypt)
- **AI/외부**: Google Gemini · Faraday · 네이버 도서검색 · 정보나루(data4library)
- **배포/품질**: Docker · Kamal 2 · Thruster / Minitest · RuboCop(omakase) · Brakeman

전체 개요·실행법·역할표는 [`README.md`](README.md), 설계 문서는 [`docs/`](docs/CLAUDE.md) 참고.

학생 메뉴 5개 재편·상점 제거·독서활동 통합·학급 미션 재설계의 상세 구현 계획은
[menu_refactor.md](menu_refactor.md)를 참고합니다.

## 디렉토리 인덱스 (마트료시카)

이 프로젝트는 폴더마다 `CLAUDE.md`를 두어, **각 CLAUDE.md만 따라 읽어도 구조를 파악**할 수 있게 되어 있습니다.

| 폴더 | 역할 | 문서 |
|------|------|------|
| `app/` | 애플리케이션 코드 (MVC + 서비스·정책·잡·프런트) | [app/CLAUDE.md](app/CLAUDE.md) |
| `config/` | Rails 설정 · 라우트 · 환경 · credentials | [config/CLAUDE.md](config/CLAUDE.md) |
| `db/` | 스키마 · 마이그레이션 · 시드 | [db/CLAUDE.md](db/CLAUDE.md) |
| `lib/tasks/` | rake 시드 태스크 (몬스터·뱃지·도서·학교·퀴즈) | [lib/tasks/CLAUDE.md](lib/tasks/CLAUDE.md) |
| `test/` | Minitest (모델·통합·정책·서비스·잡) | [test/CLAUDE.md](test/CLAUDE.md) |
| `script/` | Python 몬스터 스프라이트 생성 파이프라인 (앱 런타임과 분리) | [script/CLAUDE.md](script/CLAUDE.md) |
| `docs/` | 설계·구현·운영 문서 | [docs/CLAUDE.md](docs/CLAUDE.md) |
| `manual/` | 역할별(학생·교사·사서·교무·관리자) 최종 사용자 사용 매뉴얼 | [manual/CLAUDE.md](manual/CLAUDE.md) |

**스킵한 폴더** (코드 열람 불필요): `bin/` `public/` `vendor/` `tmp/` `log/` `storage/` `.github/` `.kamal/` 및 `script/` 하위의 `output/`·`.venv/`·`__pycache__/`.

## 유지보수 규칙 (중요)

> ⚠️ **어느 폴더든 파일이 추가·삭제되거나 역할·구조가 바뀌면, 그 폴더의 `CLAUDE.md`를 반드시 함께 갱신하세요.**
> - 하위 폴더가 새로 생기거나 사라지면, 상위 폴더 `CLAUDE.md`의 인덱스/링크도 갱신합니다.
> - 새 폴더가 "코드를 읽을 가치가 있는" 폴더라면 거기에도 `CLAUDE.md`를 새로 만들고, 상위 인덱스에 연결합니다.
> - 이 규칙은 마트료시카 구조 전체(루트 → app → 각 하위)에 재귀적으로 적용됩니다.
