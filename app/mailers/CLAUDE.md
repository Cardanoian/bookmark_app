# app/mailers/ — 트랜잭셔널 메일

'책갈피'가 보내는 **계정 인증 메일**을 담는 계층입니다. 발송은 **Resend API**(`delivery_method = :resend`,
젬의 `Resend::Railtie` 가 자동 등록)로 하며, 발신 주소는 검증 완료된 도메인의 `admin@chaekgalpi.net` 입니다.
**메일은 교직원에게만 갑니다** — 학생은 이메일 로그인 대상이 아니고(튜플 로그인) 비밀번호는 담임이
`Teacher::StudentsController#reset_password` 로 직접 초기화합니다.

## 파일
- `application_mailer.rb` — 공통 기반. `default from:` 을 **`Mail::ResendGateway.from_address`(프록)**로 두어
  발신 주소 결정을 게이트웨이 한 곳으로 모은다(ENV `MAIL_FROM` 오버라이드). `delivery_job` 을
  `MailDeliveryJob` 으로 교체해 발송 실패가 감사 원장에 남게 한다.
- `account_mailer.rb` — 두 액션. **`password_reset(user, token)`**(교직원 비밀번호 재설정,
  `edit_password_reset_url`) · **`email_verification(user, token)`**(교사 가입 인증 + 재발송 공용,
  `email_verification_url`). 만료 문구는 뷰에 하드코딩하지 않고 `@expires_in_text` 로 주입한다 —
  `User::PASSWORD_RESET_EXPIRY`(15분)·`User::EMAIL_VERIFICATION_EXPIRY`(24시간)에서 파생되므로 상수를
  바꾸면 본문이 자동으로 따라오고, 메일러 테스트가 이 일치를 검증한다(문서-코드 드리프트 차단).

본문 템플릿은 `app/views/account_mailer/*.{html,text}.erb`(멀티파트 2종씩), 레이아웃은
`app/views/layouts/mailer.{html,text}.erb` 입니다.

## 패턴·규칙
- **인라인 CSS 만** 사용한다(이메일 클라이언트 호환). 외부 이미지·웹폰트·`<style>` 규칙 금지 —
  `layouts/mailer.html.erb` 가 카드 셸과 「책갈피」 헤더를 제공하고, 각 템플릿은 그 안의 본문만 쓴다.
- **HTML·텍스트 두 파트를 항상 함께** 둔다(`.html.erb` + `.text.erb`). 한쪽만 있으면 멀티파트가
  깨지고 텍스트 전용 클라이언트에서 빈 메일이 된다(메일러 테스트가 두 파트 존재를 강제).
- **본문에 비밀번호·다이제스트·salt 를 절대 넣지 않는다**(메일러 테스트의 PII 회귀 가드).
- 발송은 `deliver_later`. **트랜잭션 블록 안에서 호출하지 않는다** — 이 앱은
  `ActiveJob::Base.enqueue_after_transaction_commit` 이 `false` 라 커밋 전에 잡이 실행돼 레코드를
  못 찾을 수 있다(`RegistrationsController#create` 주석 참조).
- 링크 호스트는 환경별 `default_url_options`(production = `chaekgalpi.net`, `protocol: https`)를 따른다.
  발신 주소도 Resend 에서 검증한 같은 운영 도메인을 사용한다.
- 키가 없으면(`Mail::ResendGateway.available? == false`) 개발·CI 는 `delivery_method = :test` 로
  실제 발송이 일어나지 않고, 이메일 인증 게이트도 함께 꺼진다(무키 완전동작 원칙).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요.
> 메일 본문 템플릿(`app/views/account_mailer/`)이 바뀌면 `app/views/CLAUDE.md` 도 함께 확인하세요.
