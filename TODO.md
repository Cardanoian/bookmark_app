# 「책갈피」 TODO

> 앞으로 해야 할 작업 정리. 최종 수정: 2026-07-07
> 참고 문서: [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) · [`docs/RAILS_PLAN.md`](docs/RAILS_PLAN.md) · [`docs/monsters.md`](docs/monsters.md) · [`docs/API_KEYS.md`](docs/API_KEYS.md)

## 현재 상태 (baseline)

- **앱 구현 Phase 0~8 완료.** 인증·역할, 독후감·AI 파이프라인, 게이미피케이션·몬스터 도감, 콘텐츠·커뮤니티, 역할별 도구(교사/사서/교육청/총괄), 배포 설정까지 구현됨.
- **테스트 401 runs / 0 failures**, rubocop 무경고, brakeman 0.
- **외부 API 키 4종 주입 완료**(Gemini·네이버·정보나루) — 암호화 credentials. 도서검색은 네이버 단독.
- 아래는 **아직 남은 작업**이다.

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

- [ ] **몬스터 도감 절반 남음** — `monsters.md`는 **24라인 × 3단계 = 72폼** 정의인데 현재 **phase:1(12라인 × 3 = 36폼)만 시드**됨. 나머지 12라인(36폼)을 `db/seeds/monsters.yml` + `monsters.rake`(phase:2)로 추가. **도감 완성 분모가 24라 필수**(현재 12라인만 있으면 `dex_complete` 영구 미달).
- [ ] **몬스터 이미지 에셋** — 현재 `image_key` 참조만 있고 실제 PNG 없음(뷰는 플레이스홀더). `monsters.md` §3의 AI 이미지 가이드로 72종 생성 → `app/assets` 배치.
- [ ] **학교 전량 시드** — 현재 축소 개발 시드(17개 시도 대표교). 실서비스는 전국 6,331교 필요 → 원본 데이터 확보 후 `lib/tasks/schools.rake` 전량 적재.
- [ ] **도서 카탈로그 확장** — 현재 추천 24 + 고전 10 = 34권. 학년·교과 연계 도서 확대 검토.

## 🔵 외부 API 실연동 검증 (키 주입됨 · 실호출 미검증)

> 키는 넣었지만 **아직 실제 API를 한 번도 호출하지 않았다.** 응답 필드 매핑은 문서 기반 가정이므로 첫 실호출 때 검증 필요. 실패해도 폴백(로컬 캐시·규칙기반·CSV)은 무중단 동작.

- [ ] **Gemini 실응답 검증** — 실제 호출 시 첨삭 5축 파싱 / OCR / 진위 / 퀴즈 응답 JSON 구조가 `Ai::*` 서비스의 파싱과 일치하는지 확인.
- [ ] **네이버 도서검색 실응답 검증** — 필드 매핑(title/author/image/isbn) 실데이터 확인. `app/services/books/search_service.rb`.
- [ ] **정보나루 실응답 검증** — `loanItemSrch` 응답(`docs[].doc`: bookname/isbn13/loan_count) + 직전 달 `startDt/endDt` 파라미터 실동작 확인. `app/services/library/data4library_service.rb`.

## 🟢 기능 마무리·개선

- [ ] **독후감 공유 토글 정합성** — `reports/show`의 버튼 라벨이 `shared? ? "공유 취소" : "우수작 공유"`인데 share 액션이 실제 토글(취소)까지 하는지 확인/수정.
- [ ] **게시판 글 좋아요** — `forum_post`에 모델 메서드만 있고 라우트·UI 없음. 필요 시 라우트·컨트롤러·뷰 추가.
- [ ] (오너가 원하는 추가 기능·개선 항목을 여기에)

## 🔵 품질·테스트·운영

- [ ] **브라우저/시스템 테스트** — 현재 headless Chrome 부재로 model/request/integration/policy 테스트만. Stimulus·Turbo 상호작용 E2E 커버리지 추가 검토.
- [ ] **접근성(UDL)** — STT/TTS·원고지·낭독 녹음 등 실기기 검증.
- [ ] **성능** — 대시보드·랭킹·도감의 N+1 쿼리 점검, 인덱스 확인.
- [ ] **모니터링·에러 트래킹** — 프로덕션 로깅/에러 리포팅 도구 도입 검토.
