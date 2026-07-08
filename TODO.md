# 「책갈피」 TODO

> 앞으로 해야 할 작업 정리. 최종 수정: 2026-07-08
> 참고 문서: [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) · [`docs/RAILS_PLAN.md`](docs/RAILS_PLAN.md) · [`docs/monsters.md`](docs/monsters.md) · [`docs/API_KEYS.md`](docs/API_KEYS.md)

## 현재 상태 (baseline)

- **앱 구현 Phase 0~8 완료.** 인증·역할, 독후감·AI 파이프라인, 게이미피케이션·몬스터 도감, 콘텐츠·커뮤니티, 역할별 도구(교사/사서/교육청/총괄), 배포 설정까지 구현됨.
- **테스트 497 runs / 0 failures**, rubocop 무경고, brakeman 0. (전체 점검 Phase 0~3 하드닝 + Gemini API 실동작화 + 몬스터 도감 전량 시드 반영)
- **외부 API 키 4종 주입 완료**(Gemini·네이버·정보나루) — 암호화 credentials. 도서검색은 네이버 단독.
- 아래는 **아직 남은 작업**이다.

---

## ⭐ 다음 추천 실행 순서

> 남은 작업을 **리스크·의존성·비용** 기준으로 정렬한 권장 순서(강제 아님, 오너 우선순위에 따라 재배열 가능). **각 항목의 상세 정의·기술 배경은 아래 카테고리 섹션에 있고, 여기서는 순서 근거만 적는다.**
>
> 최근 완료: 하드닝 Phase 0~3 5커밋 로컬 main 병합(미push) · 외부 API 3종 실호출 검증(Gemini 결함 2건 수정) · **몬스터 도감 24라인 72폼 전량 시드(dex_complete 보상 루프 닫힘, 2026-07-08)** · **OCR 실사진 라이브 검증(손글씨 2장 정확 인식, 2026-07-08)** → 이로써 4종 API 경로 전량 실검증 완료.

1. **🔴 배포 준비** *(→ 배포)* — 드로플릿·레지스트리 자격이 확보되면 착수하는 마일스톤.
2. **🔵 모니터링·에러 트래킹** *(→ 품질·운영)* — 아래 3.2 착수 판단의 관측 근거라 배포와 함께 세팅 권장.
3. **`git push origin main`** *(자격 확보 시 상시)* — 현재 로컬 main이 origin보다 앞서 있음(미push). 인증되면 원격 동기화.

---

## 🔴 배포 (프로덕션 올리기 전 필수)

- [ ] **실제 원격 배포** — `kamal setup` → `kamal deploy`. 현재는 로컬 부팅 검증까지만 완료(드로플릿·레지스트리 자격 부재로 미실행).
- [ ] **실 도메인 설정** — `config/deploy.yml`의 `proxy.host`가 플레이스홀더(`chaekgalpi.example.com`). 실 호스트로 교체 + DNS + SSL(kamal-proxy Let's Encrypt 자동).
- [ ] **메일러 호스트** — `config/environments/production.rb`의 `default_url_options` host가 `example.com`. 실 도메인으로 교체(비밀번호 재설정 등 메일 발송 시 SMTP 자격도).
- [ ] **프로덕션 시크릿 주입** — 서버에 `RAILS_MASTER_KEY`(= `config/master.key` 내용)만 주입하면 credentials 자동 복호화. 절차: [`docs/API_KEYS.md`](docs/API_KEYS.md) §3.2.
- [ ] **Active Storage 프로덕션 스토리지** — 현재 local disk 서비스. 서버 재생성 시 업로드(사진·낭독 녹음) 유실 방지를 위해 DigitalOcean Spaces(S3 호환) 등 영속 스토리지 검토.
- [ ] **SQLite 데이터 영속성** — `storage/production*.sqlite3` 4개 DB(primary/cache/queue/cable)의 kamal 볼륨 마운트·백업 전략 확인.
- [ ] **잡 워커** — 현재 `SOLID_QUEUE_IN_PUMA: true`(Puma 내 실행)로 단일 서버엔 충분. 트래픽 증가 시 전용 job 서버 분리(`deploy.yml`의 `servers.job`).

## 🟡 콘텐츠·데이터 완성

- [x] ~~**몬스터 도감 절반 남음**~~ — 완료(2026-07-08). `db/seeds/monsters.yml` 24라인에 `phase` 명시(1·2 각 12라인) + `MonsterSeeder.seed_all!`(rake `monsters:seed`)로 **72폼 전량 시드**. `dex_complete`(분모 24) 이제 도달 가능 → 완성 보상 루프 닫힘. 테스트 3건 추가(전량 시드 무결성·phase2 조건·24라인 dex_complete). **단, 이건 데이터 시드만이며 아트 에셋(PNG)은 아래 항목에서 별도 제작 필요.**
- [ ] **몬스터 이미지 에셋** — 현재 `image_key` 참조만 있고 실제 PNG 없음(뷰는 플레이스홀더). `monsters.md` §3의 AI 이미지 가이드로 72종 생성 → `app/assets` 배치.
- [ ] **학교 전량 시드** — 현재 축소 개발 시드(17개 시도 대표교). 실서비스는 전국 6,331교 필요 → 원본 데이터 확보 후 `lib/tasks/schools.rake` 전량 적재.
- [ ] **도서 카탈로그 확장** — 현재 추천 24 + 고전 10 = 34권. 학년·교과 연계 도서 확대 검토.

## 🔵 외부 API 실연동 검증 (2026-07-07 실호출 완료)

> 세 API 모두 **실제로 호출해 응답 필드 매핑을 검증**했다. 검증 중 Gemini 경로에서 치명 결함 2건을 발견·수정(아래). 실패 시 폴백(로컬 캐시·규칙기반·CSV)은 여전히 무중단 동작.

- [x] **Gemini 실응답 검증** — 5축 첨삭/퀴즈/진위 응답 JSON 구조가 `Ai::*` 파싱과 일치 확인(rubric 5축 content·emotion·life·structure·spelling, questions[prompt/choices/answer_index], suspicion/reasons). **검증 중 결함 2건 수정:**
  - 🐞 **systemInstruction 형식 오류** — `GeminiClient` 가 `systemInstruction` 을 문자열로 보내 **모든** system_instruction 사용 호출(첨삭·퀴즈·진위·OCR)이 HTTP 400 → 조용히 폴백. 즉 AI 기능 전부가 규칙기반/오프라인으로만 동작 중이었음. `{ parts: [{ text: }] }` Content 구조체로 감싸 수정.
  - 🐞 **타임아웃 과소(8s)** — 5축 첨삭 실측 지연 ~16s 인데 per-attempt 8s 라 위 수정 후에도 첨삭은 매 시도 타임아웃 → 폴백. 30s 로 상향(첨삭·OCR 은 백그라운드 잡, 동기 경로는 8s 미만이라 무영향).
  - [x] **OCR(사진→텍스트) 실이미지 검증 완료(2026-07-08)** — 실제 손글씨 독후감 사진 2장(피그말리온·강아지똥, 원고지)을 `Ai::OcrService` 프로덕션 경로로 라이브 호출(gemini-2.5-flash Vision). **인식 정확도 우수**(피그말리온 434자/7.5s, 강아지똥 650자/9.3s — 오탈자 거의 없음). `response["text"]` 매핑·Base64 `inlineData` 인코딩·JSON 파싱 정상 확인. **부수 성과:** 강아지똥이 9.3s라 과거 8s 타임아웃이면 실패 → 30s 상향 수정(Gemini 하드닝)의 필요성이 실측으로 재확인됨.
- [x] **네이버 도서검색 실응답 검증** — HTTP 200, `items[]` 의 title/author/publisher/image/isbn/description 6개 필드 전부 존재·매핑 일치. isbn13 단일값 정상. `app/services/books/search_service.rb`.
- [x] **정보나루 실응답 검증** — 과거 확정 기간(예: 2025-06) HTTP 200, `response.docs[].doc` 의 bookname/isbn13/loan_count 매핑 일치(loan_count 는 문자열→`.to_i`). **주의:** 직전 달 데이터가 아직 미집계면 8s 타임아웃 → CSV 폴백(정상 열화). `app/services/library/data4library_service.rb`.

## 🟢 기능 마무리·개선

- [ ] **독후감 공유 토글 정합성** — `reports/show`의 버튼 라벨이 `shared? ? "공유 취소" : "우수작 공유"`인데 share 액션이 실제 토글(취소)까지 하는지 확인/수정.
- [ ] **게시판 글 좋아요** — `forum_post`에 모델 메서드만 있고 라우트·UI 없음. 필요 시 라우트·컨트롤러·뷰 추가.
- [ ] (오너가 원하는 추가 기능·개선 항목을 여기에)

## 🔵 품질·테스트·운영

- [ ] **브라우저/시스템 테스트** — 현재 headless Chrome 부재로 model/request/integration/policy 테스트만. Stimulus·Turbo 상호작용 E2E 커버리지 추가 검토.
- [ ] **접근성(UDL)** — STT/TTS·원고지·낭독 녹음 등 실기기 검증.
- [ ] **성능** — 대시보드·랭킹·도감의 N+1 쿼리 점검, 인덱스 확인. (전체 점검 Phase 3에서 3.1 랭킹 그룹 SQL·3.3 카운터캐시·3.4 대시보드 집계+페이지네이션·3.5 인덱스 반영 완료.)
- [ ] **(성능·의도적 보류) 3.2 게임화 재계산 백그라운드 이관** — `award_points → refresh_badges!/check_evolution!/ReadingStats` 재계산을 웹 요청 스레드에서 백그라운드 잡으로 이관.
  - **지금 보류하는 이유:** ① 2.2 메모이제이션으로 요청당 쿼리는 이미 감소, ② Architect 분석상 백그라운드 이관은 웹 응답 **지연**만 완화하고 단일 SQLite **쓰기 경합**은 완화 못 함(잡도 동일 primary writer), ③ 비동기화 시 뱃지·레벨업·진화·랭킹이 **즉각 반영되지 않아**(eventual consistency) 미성년자 게임화의 즉각 피드백 UX가 저하됨.
  - **착수 트리거(이 중 하나라도 관측되면):** 프로덕션 실부하에서 SQLite `database is locked`(쓰기 타임아웃) 발생 / 퀴즈 완료·교사 점수부여 응답이 체감상 지연 / 동시 쓰기 병목이 모니터링에 잡힐 때.
  - **착수 시 필수:** 게임화 즉각성 통합 테스트를 `perform_enqueued_jobs` 로 재작성, 뱃지·진화의 "한 박자 늦은" 표시를 UX(로딩/폴링/Turbo Stream)로 보완.
- [ ] **모니터링·에러 트래킹** — 프로덕션 로깅/에러 리포팅 도구 도입 검토. 위 3.2 항목의 **착수 트리거(SQLite `database is locked`·응답 지연·쓰기 병목)를 실측으로 포착**하는 관측 인프라 역할을 겸한다.
