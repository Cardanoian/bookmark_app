# docs/ — 설계·구현·운영 문서 인덱스 (한국어)

'책갈피' 프로젝트의 운영 가이드·설계 기록·콘텐츠 시드를 담은 한국어 문서 모음이다. 외부 API 키 운영·배포·AI 모델 선정·디자인 시스템 기록부터 반려 몬스터 도감 시드·해금 규칙·사용자 안내서까지 커버한다.

## 파일
- `CLOUD_DEPLOYMENT_COMPARISON.md` — DigitalOcean·NAVER Cloud·AWS EC2·Oracle Cloud의 리전·비용·스토리지·운영성을 비교하고 HTTPS 이메일 API와 Rails Action Mailer 연동을 설명하는 배포 의사결정 가이드.
- `DEMO_DEPLOYMENT.md` — **심사·시연용 배포 런북(운영자용)**. DigitalOcean + Kamal 로 심사위원 체험 인스턴스를 띄우는 절차. `RAILS_MASTER_KEY` 만으로 무키 동작하며, **`DEMO_DEPLOYMENT=1` 시드**로 production 에서도 5역할 계정 + 39학급 데모 데이터를 적재한다(운영 배포엔 미유입). deploy.yml/production.rb 수정·도메인 연결·데이터 적재·초기화·종료 정리·소스 zip 제출(`git archive`)까지 커버.
- `JUDGE_GUIDE.md` — **심사위원 체험 안내문(제출물 동봉)**. 접속 후 5개 역할 로그인표(학생 튜플 로그인 포함)와 5분 둘러보기 코스. 온라인 데모·로컬 실행 양쪽에서 공통으로 쓴다. 운영자 기입란(URL·총괄관리자 비번·연락처) 표시.
- `JUDGE_RUN_LOCAL.md` — **소스코드 직접 실행 안내(Windows 심사위원용)**. 방법 A=**Docker Desktop `docker compose up` 한 줄**(권장, 비밀키·API키 불필요·개발 모드), 방법 B=WSL2+mise 직접 설치(참고). 루트 `Dockerfile.dev`·`compose.yaml`·`bin/docker-dev-entrypoint` 와 정합. 로컬 총괄관리자=admin@example.com/changeme1234(무키 폴백).
- `API_KEYS.md` — 외부 API 키 운영 가이드. 앱은 `ENV 우선·credentials 폴백`으로 키를 읽으며(credentials 가 기본 저장소), 키가 없어도 폴백으로 완전히 동작(키 주입 방법·ENV 변수명·보안 규칙).
- `AI_MODEL_SELECTION.md` — **AI 첨삭 Gemini 모델 선정 근거**. 후보 6종(3.1-pro~2.5-flash)을 학년군별 독후감 6편 × 5축 첨삭 실제 호출로 비교(학년 성취기준 안전성·비용/1,000건·지연·문체)한 뒤 `gemini-3.5-flash-lite` 를 선정한 의사결정 기록. 모델은 `app/services/ai/gemini_client.rb` 의 `MODEL` 상수 한 곳에서 지정.
- `reading_discussion.md` — 독서 토론(Topic/ForumPost) 표면화 설계 결정 기록(ADR). 메뉴 재편 후 진입점이 사라진 토론 스택을 책 앵커드 진입점 + 아동안전 최소보강(Option B)으로 되살린 근거·경계격리·잔존리스크.
- `ocr_photo_display_plan.md` — **OCR 독후감 사진 512 표시 계획 + 구현 기록(ADR 포함, 상태 `implemented`, 2026-07-27)**. OCR 손글씨 사진을 교사 검토(`teacher/reviews/show`)·학생 상세(`reports/show`)에 표시용 512 variant로 노출한다. 확정 결정: 원본 보존 + `resize_to_limit` variant, 아동 PII 바이트를 **인증 프록시 컨트롤러**(`ReportPhotosController#show`, `authorize :show?` — 페이지 인가 미러)로 fail-closed 서빙(**Option B 채택**, Option A 서명 URL obscurity는 기각), 확대는 1600px 유계, root 체인 고쳐쓰기 승계, `_report_detail`(방송 파티셜)·스키마 무변경, `urls_expire_in` 미설정. **§8 구현 기록**에 산출물 목록·검증 결과(전체 테스트/RuboCop/Brakeman 그린)와 **계획 대비 편차 1건**(libvips 부재 시 `.processed` 가 `StandardError` 아닌 `LoadError` 를 던져 스케치의 `rescue => e` 로는 500 → `rescue StandardError, LoadError` 로 구현), libvips 없는 호스트용 `ActiveStorage::Attachment#variant` 테스트 시임, 남은 수동 e2e 확인 항목을 정리했다. 진짜 저장 이슈인 원본 retention/purge는 범위 밖 후속(미착수). ralplan 3자 합의(Planner·Architect·Critic APPROVE) 산출물.
- `책갈피_정밀분석_보완보고서.pdf` — 외부 감사 리포트(2026-07-22, 대회 출품 대비). P0/P1/P2 보완 권고·심사기준별 준비도·D-9 실행 로드맵·수용 테스트 체크리스트.
- `보완보고서_이행현황.md` — 위 감사 리포트의 각 권고를 **실제 코드베이스와 대조**한 이행 현황·잔여 과제 문서(2026-07-23 기준). P1 의사결정까지 반영해 **P1-3 감사 로그, P1-5 닉네임·랭킹 옵트인/자기성장 기본, P1-8 성장 시계열은 완료**, P1-4는 `accept="image/*"`·현행 서버 매직바이트/크기 검증을 유지(추가 EXIF·픽셀 처리는 하지 않는 위험 수용), 나머지 제외 항목은 적용 제외로 명시한다.
- `monsters.md` — 반려 몬스터 도감 **시드 설계서**. 24라인×3단계=72폼의 종·진화 라인·조건·AI 이미지 가이드(`monsters:seed` 근거, `script/monster.json`과 정합).
- `monster_unlocks.md` — 몬스터 24개 라인의 **자동 해금 규칙 설계서**. 레어도별 난이도, 일일 독후감·게임 활동 집계 계약, 전체 해금 조건과 자동 지급 흐름을 정의한다.
- `monster_guide.md` — 학생·학부모용 **도감 안내서**(친근한 어투). 몬스터가 무엇이고 어떻게 만나고 진화하는지 소개.
- `gamification_education_proposals.md` — 게임·도감 기능의 **교육 효과 강화 개선안 제안서**(2026-07-25, 제안 단계·코드 미변경). 현재 시스템 진단(강점·공백)과 설계 원칙, A~F 6개 영역 18개 개선안(몬스터 코치·낱말 먹이·독서 여정·자기 예측 채점·학급 수호 몬스터·몬스터 통신문 등)의 상세 설계·구현 방향·3웨이브 로드맵·교육학적 근거.
- `2026 2월호_2026 상반기 추천도서목록 홈페이지 업로드용.xlsx` — 학생 홈 공식 추천도서 초기 원본. 전체목록의 어린이 4개 분과 203권을 `Recommendations::Importer`가 최초 시드와 총괄관리자 업로드 양식 검증에 사용한다.

## 자료 이미지
- `피그말리온.jpeg`·`강아지똥.jpeg` — 문서 작업에 딸린 삽화/예시용 이미지 자료(마크다운 본문에 임베드되어 있지는 않음).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
