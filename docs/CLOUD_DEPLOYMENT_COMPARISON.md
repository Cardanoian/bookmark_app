# 「책갈피」 클라우드 배포·메일러 비교 가이드

> **목적**: 「책갈피」 Rails 앱의 배포 클라우드를 선택하고 프로덕션 이메일 발송 방식을 이해·구현하기 위한 운영 가이드  
> **비교 대상**: DigitalOcean · NAVER Cloud Platform · AWS EC2 · Oracle Cloud Infrastructure  
> **최종 확인**: 2026-07-12

> [!IMPORTANT]
> 클라우드 요금과 무료 한도는 수시로 바뀐다. 아래 금액은 작성일의 공식 공개 자료를 바탕으로 한 비교용 스냅샷이다. 실제 생성 직전에는 리전·서버·디스크·공인 IP·트래픽·백업·세금을 포함한 월 예상액을 각 사 계산기에서 다시 확인한다.

## 0. 결론 먼저

현재 「책갈피」의 첫 배포에는 **DigitalOcean SGP1의 2GB x86 Droplet**이 가장 현실적이다.

- 기존 `config/deploy.yml`과 운영 문서가 DigitalOcean + Kamal 2를 기준으로 준비되어 있다.
- 단일 서버에 Rails·Puma·Solid Queue·SQLite를 함께 실행하기 쉽다.
- 월 비용과 포함 트래픽이 단순하고 예측하기 쉽다.
- 단점은 한국 서버 리전이 없고 Droplet의 SMTP 포트가 차단된다는 점이다.
- 이메일이 필요해지면 서버에서 직접 SMTP를 쓰지 않고 **Resend 같은 외부 HTTPS 이메일 API**를 연결한다.

상황별 권장은 다음과 같다.

| 상황                                        | 우선 선택        | 이유                                                    |
| ------------------------------------------- | ---------------- | ------------------------------------------------------- |
| 빠른 첫 배포·파일럿·포트폴리오              | **DigitalOcean** | 가장 단순한 Kamal 운영, 예측 가능한 소형 서버 비용      |
| 한국 학교 실사용·국내 데이터 보관 우선      | **NAVER Cloud**  | 한국 리전, 원화 결제, Object Storage와 자체 메일 서비스 |
| 조직이 이미 AWS를 사용하거나 장기 확장 예상 | **AWS EC2**      | 서울 리전, S3·SES·CloudWatch 등 가장 넓은 생태계        |
| 개인 실험·최저 비용·ARM 운영 감수           | **Oracle Cloud** | Always Free 범위와 무료 트래픽이 큼                     |

Oracle Always Free는 매력적이지만 무료 자원은 용량 부족으로 생성되지 않을 수 있고 SLA·정식 지원이 없다. 학교 대상 프로덕션의 유일한 서버보다는 개발·스테이징·개인 데모 용도로 보는 편이 안전하다.

---

## 1. 이 프로젝트의 배포 전제

클라우드 선택은 현재 저장소의 실제 구조를 기준으로 판단해야 한다.

- Rails 8 + Docker + Kamal 2 단일 서버 배포
- `builder.arch: amd64`
- Puma 내부에서 Solid Queue 실행(`SOLID_QUEUE_IN_PUMA: true`)
- primary/cache/queue/cable 네 개의 SQLite DB
- SQLite와 local Active Storage를 `/rails/storage` 영속 볼륨에 함께 저장
- 학생 독후감 사진·낭독 녹음 업로드 가능
- 서버가 외부 Gemini·네이버 검색·정보나루 API를 호출
- 현재 실제 이메일 발송 기능과 사용자 이메일 필드는 없음

이 구조에서는 Kubernetes나 관리형 DB보다 다음 네 가지가 먼저 중요하다.

1. Docker를 실행할 수 있는 안정적인 Linux VM
2. SQLite 쓰기와 Rails 프로세스를 감당할 최소 2GB 메모리
3. `/rails/storage`의 영속성과 별도 백업
4. 업로드 파일을 서버 밖 Object Storage로 옮길 경로

---

## 2. 네 클라우드 한눈에 비교

| 항목                | DigitalOcean                              | NAVER Cloud                                      | AWS EC2                                      | Oracle Cloud                                        |
| ------------------- | ----------------------------------------- | ------------------------------------------------ | -------------------------------------------- | --------------------------------------------------- |
| 한국 내 컴퓨트 리전 | 없음. 가까운 선택은 Singapore `SGP1`      | 한국 리전                                        | Seoul `ap-northeast-2`                       | Seoul `ap-seoul-1`, Chuncheon `ap-chuncheon-1`      |
| 이 앱의 시작 사양   | Basic 1 vCPU·2GB·50GB                     | Classic Compact-g1 1 vCPU·2GB·50GB 또는 VPC 서버 | x86 `t3.small` 계열 2 vCPU·2GiB + EBS        | 유료 x86 Flex 또는 Always Free ARM 2 OCPU·12GB 범위 |
| 비용 구조           | VM·로컬 SSD·대량 전송량이 한 플랜에 포함  | 서버·공인 IP·트래픽·백업이 별도일 수 있음        | EC2·EBS·IPv4·스냅샷·트래픽을 각각 계산       | Always Free 또는 OCPU·메모리·블록 볼륨 종량제       |
| 네트워크            | Droplet 플랜에 전송량 포함                | 인터넷 아웃바운드 월 20GB 무료 후 종량           | 리전별 인터넷 전송 요금 별도                 | 인터넷 아웃바운드 월 10TB 무료                      |
| Object Storage      | Spaces: 월 $5 기본, 250GiB·1TiB 전송 포함 | 사용량 기반, 한국 리전, S3 API                   | S3: 기능이 풍부하나 요청·저장·전송 세분 과금 | Always Free 범위 존재                               |
| 관리형 메일         | 없음                                      | Cloud Outbound Mailer                            | Amazon SES                                   | OCI Email Delivery                                  |
| 현재 amd64 이미지   | 그대로 사용                               | 그대로 사용                                      | t3 등 x86이면 그대로 사용                    | Ampere A1은 `arm64` 변경 필요                       |
| 운영 난이도         | 낮음                                      | 보통                                             | 높음                                         | 보통~높음                                           |
| 추천 용도           | 첫 프로덕션·소규모 운영                   | 국내 학교 서비스                                 | 조직형·확장형 운영                           | 실험·스테이징·극저비용 운영                         |

> 서버 사양이 완전히 같지 않으므로 숫자만 단순 환산하면 안 된다. 특히 AWS는 EBS와 공인 IPv4가 별도이고, NAVER Cloud는 Classic과 VPC의 가격 차이가 크며, Oracle 무료 ARM은 현재 x86 이미지와 아키텍처가 다르다.

---

## 3. 클라우드별 상세 비교

### 3.1 DigitalOcean

권장 시작 구성:

- 리전: Singapore `SGP1`
- 서버: Basic Droplet 1 vCPU·2GB·50GB
- 이미지 레지스트리: DOCR 또는 GHCR
- 업로드: 초기 local, 학교 실사용 전 Spaces 전환
- 백업: 주간 Droplet 백업 + 별도 SQLite 논리 백업
- 메일: Resend·SendGrid·Postmark 같은 외부 HTTPS API

공식 요금표 기준 Basic 1 vCPU·2GB·50GB는 월 $12이며 2,000GiB 전송량을 포함한다. 주간 Droplet 이미지 백업은 서버 비용의 20%가 추가된다. Spaces는 월 $5에 250GiB 저장 공간과 1,024GiB 아웃바운드가 포함된다.

장점:

- 가격표와 콘솔이 단순하다.
- 공인 IPv4와 로컬 SSD가 Droplet에 포함된다.
- 현재 Kamal 설정과 `amd64` 빌드를 거의 그대로 사용할 수 있다.
- 단일 서버를 만들고 SSH·Docker만 준비하면 배포할 수 있다.
- DOCR Starter는 단일 저장소·500MiB까지 무료다. 이미지가 크면 Basic이나 GHCR을 사용한다.

단점:

- 한국 Droplet 리전이 없다. 서울 CDN PoP가 있어도 동적 Rails 요청은 싱가포르 서버까지 간다.
- Droplet은 SMTP 25·465·587 포트를 기본 차단한다.
- 자체 트랜잭션 이메일 서비스가 없다.
- 학생 사진·음성을 싱가포르 리전에 저장한다. 국내 보관이 내부 원칙이면 맞지 않는다.

현재 단계에서는 **가장 추천**한다. 앱이 단일 서버 구조이고 아직 대규모 트래픽이 없으므로 복잡한 클라우드 기능보다 빠른 배포와 쉬운 복구가 더 중요하다.

### 3.2 NAVER Cloud Platform

가능한 시작 구성:

- 리전: 한국
- 저비용: Classic Compact-g1 1 vCPU·2GB·50GB
- 현대적 VPC: 운영 보장 서버 중 High CPU-g2 2 vCPU·4GB 이상 검토
- 업로드: 한국 리전 Object Storage
- 메일: Cloud Outbound Mailer HTTPS API

공식 표의 Classic Compact-g1은 월 26,000원이며 공인 IP는 월 4,032원이다(VAT 별도). VPC의 운영용 High CPU-g2 2 vCPU·4GB는 디스크에 따라 대략 월 69,120~72,000원부터 시작한다. Micro는 신규 계정 체험용이며 가용성과 성능이 보장되지 않는다.

장점:

- 한국 사용자의 동적 요청과 업로드 지연이 짧다.
- 한국 리전에 사진·음성·백업을 둘 수 있다.
- 한국어 콘솔·문서·고객 지원과 원화 청구가 편하다.
- Object Storage가 S3 API를 제공해 Rails Active Storage와 연결할 수 있다.
- Cloud Outbound Mailer가 월 1,000건 무료, 초과 건당 0.45원으로 저렴하다(VAT 별도).

단점:

- 저렴한 Classic과 현대적인 VPC 사이의 비용 차이가 크다.
- VPC·ACG·공인 IP·스토리지·권한을 따로 이해해야 한다.
- 관리형 Backup은 최소 100GB·월 30,000원이라 소규모 SQLite 앱에는 과할 수 있다.
- Cloud Outbound Mailer는 SMTP 주소만 넣는 방식이 아니라 HTTP API 연동이 필요하다.

실제 학교와 계약하거나 **학생 업로드의 국내 리전 보관을 운영 원칙으로 정할 때** 가장 설득력 있다. 첫 파일럿 단계에서는 DigitalOcean보다 비용과 초기 설정 부담이 크다.

### 3.3 AWS EC2

권장 시작 구성:

- 리전: Seoul `ap-northeast-2`
- 서버: x86 `t3.small` 계열 2 vCPU·2GiB부터 검토
- 디스크: EBS gp3
- 주소: Elastic IP 또는 인스턴스 공인 IPv4
- 업로드: S3
- 메일: Amazon SES HTTPS API
- 모니터링: CloudWatch

AWS는 EC2 가격만 보면 전체 비용을 알 수 없다. 다음을 함께 계산해야 한다.

- EC2 인스턴스 시간
- EBS gp3 용량과 스냅샷
- 공인 IPv4: 시간당 $0.005, 한 달 약 $3.65
- 인터넷 아웃바운드
- S3 저장·요청·전송
- CloudWatch 로그 보존량

서울 리전의 실제 금액은 AWS Pricing Calculator에서 위 항목을 함께 넣어 산정한다.

장점:

- 서울 리전에 EC2·S3·SES를 함께 둘 수 있다.
- 서비스가 커질 때 RDS·ElastiCache·CloudFront·WAF 등으로 확장하기 쉽다.
- IAM 권한 분리와 감사·모니터링 생태계가 가장 풍부하다.
- `aws-actionmailer-ses`를 이용하면 Rails에서 SES HTTPS API를 공식 지원 경로로 사용할 수 있다.

단점:

- 작은 단일 서버 앱에도 선택지와 과금 항목이 많다.
- IAM·VPC·Security Group·EBS·Elastic IP를 이해해야 한다.
- 로그·스냅샷·트래픽 같은 부가 비용을 놓치기 쉽다.
- EC2의 공개 인터넷 대상 SMTP 25번은 기본 제한된다. SES API를 쓰면 이 제한과 무관하다.

기관이 이미 AWS를 사용하거나 향후 관리형 DB·고가용성·조직형 IAM이 확실히 필요하다면 좋다. 현재 규모만 놓고 보면 DigitalOcean보다 운영 복잡도가 크다.

### 3.4 Oracle Cloud Infrastructure

가능한 시작 구성:

- 리전: Seoul `ap-seoul-1`
- 무료 ARM: Ampere A1 합계 2 OCPU·12GB
- 무료 x86: VM.Standard.E2.1.Micro 최대 2대, 각 1GB
- 블록 스토리지: Always Free 합계 200GB와 볼륨 백업 5개
- Object Storage: 계정 상태에 따른 Always Free 범위
- 메일: OCI Email Delivery HTTPS API

2026-06-29 갱신된 공식 문서 기준 Ampere A1 Always Free 한도는 **합계 2 OCPU·12GB**다. 과거 자료에 흔한 4 OCPU·24GB 정보와 다르므로 현재 공식 문서를 기준으로 한다.

장점:

- 무료 범위에서 이 앱을 실행할 만큼 ARM 메모리가 넉넉하다.
- Always Free 블록 볼륨 200GB와 볼륨 백업 5개가 제공된다.
- 공용 인터넷 아웃바운드가 월 10TB까지 무료다.
- 서울과 춘천 리전이 있으며 Email Delivery도 HTTPS 제출을 지원한다.
- Email Delivery는 Always Free로 월 3,000건 발송을 제공한다.

단점:

- Always Free 인스턴스는 `out of host capacity`로 생성이 안 될 수 있다.
- 무료 계정에는 SLA와 정식 기술 지원이 없다.
- 30일 이상 유휴 계정은 정지·종료 대상이 될 수 있다.
- Ampere A1은 ARM이므로 `builder.arch: amd64`를 `arm64`로 바꾸고 이미지·gem 호환성을 다시 검증해야 한다.
- 무료 x86 Micro의 1GB 메모리는 Rails·Puma·Solid Queue를 한 서버에서 돌리기에 빠듯하다.
- IAM 정책·VCN·보안 목록·NSG 등 OCI 고유 개념의 학습 비용이 있다.

ARM 빌드를 감수하는 개인 데모·스테이징에는 비용 효율이 좋다. 무료 용량의 확보 가능성과 지원 부재 때문에 **학교 프로덕션의 단일 장애점**으로 삼는 것은 권하지 않는다.

---

## 4. 추천 배포안

### A안 — 현재 가장 현실적인 첫 배포

~~~text
사용자(한국)
   ↓ HTTPS
DigitalOcean SGP1 Droplet 2GB
   ├─ Kamal Proxy + Rails + Puma
   ├─ Solid Queue in Puma
   ├─ SQLite 4개 DB
   └─ /rails/storage Docker volume
        ├─ 매일 SQLite 백업 → 외부 Object Storage
        └─ 업로드 증가 시 Active Storage → Spaces

Rails ── HTTPS 443 ── Resend ── Gmail/Naver Mail
~~~

월 고정비를 낮게 유지하면서 현재 설정을 가장 적게 바꾸는 안이다.

### B안 — 국내 학교 실사용 우선

~~~text
사용자(한국)
   ↓ HTTPS
NAVER Cloud 한국 리전 서버
   ├─ Kamal Proxy + Rails + Puma
   ├─ SQLite + 별도 Object Storage 백업
   └─ Active Storage → NCP Object Storage

Rails ── HTTPS API ── Cloud Outbound Mailer
~~~

국내 리전·한국어 운영·메일·스토리지를 한 사업자 안에서 관리하기 쉽다.

### C안 — AWS 조직 표준

~~~text
Route 53 또는 외부 DNS
   ↓
EC2 Seoul + EBS gp3
   ├─ Kamal + Rails
   ├─ S3 Active Storage
   ├─ SES API
   └─ CloudWatch
~~~

장기 확장성은 가장 좋지만 현재 앱 규모에는 구성 요소가 많다.

### D안 — Oracle 무료 실험

~~~text
OCI Seoul Ampere A1 (ARM)
   ├─ arm64 Docker 이미지
   ├─ Always Free Block Volume
   ├─ Object Storage 백업
   └─ OCI Email Delivery API
~~~

비용은 가장 낮지만 무료 자원 확보와 ARM 호환성 검증을 전제에 포함해야 한다.

---

## 5. 메일러를 가장 쉽게 이해하기

### 5.1 현재 앱은 아직 실제 메일을 보내지 않는다

현재 저장소에는 `ApplicationMailer`의 기본 틀만 있고 실제 메일러 클래스나 발송 호출이 없다. `users` 테이블에도 이메일 컬럼이 없다. 학생 비밀번호는 교사·관리자가 임시 비밀번호로 초기화해 화면에서 전달한다.

따라서 **첫 배포는 이메일 서비스 없이도 가능**하다. 메일러 설정은 성인 역할의 가입 안내·비밀번호 재설정·운영 알림을 추가할 때 진행하면 된다.

권장 이메일 정책:

- 학생: 이메일 미수집, 교사가 비밀번호 초기화
- 교사·학교 관리자·사서: 이메일 선택 또는 필수
- 교육청·총괄 관리자: 이메일 필수
- 이메일 기반 비밀번호 재설정: 성인 역할에만 제공

### 5.2 `mailer host`는 두 가지 의미가 섞이기 쉽다

Rails의 다음 설정은 **메일 발송 서버 주소가 아니다**.

~~~ruby
config.action_mailer.default_url_options = {
  host: "chaekgalpi.kr",
  protocol: "https"
}
~~~

이 `host`는 메일 안의 링크를 만드는 **책갈피 웹사이트 주소**다.

~~~text
https://chaekgalpi.kr/password_resets/abc123
~~~

실제 메일을 접수하는 곳은 별도의 이메일 API 주소다.

| 이름                | 예시                            | 역할                                |
| ------------------- | ------------------------------- | ----------------------------------- |
| 앱 호스트           | `chaekgalpi.kr`                 | 이메일 본문의 로그인·재설정 링크    |
| 발신 주소           | `no-reply@chaekgalpi.kr`        | 사용자가 보는 보내는 사람           |
| 이메일 API endpoint | `https://api.resend.com/emails` | Rails가 발송을 요청하는 전문 서비스 |

### 5.3 SMTP와 HTTPS 이메일 API의 차이

전통적인 SMTP 방식:

~~~text
Rails ── SMTP 25/465/587 ── 메일 서버 ── 수신자
~~~

HTTPS API 방식:

~~~text
Rails ── HTTPS 443 + JSON ── 이메일 업체 ── 수신자
~~~

DigitalOcean은 SMTP 25·465·587을 차단하지만 일반 웹 통신인 HTTPS 443은 사용할 수 있다. Rails는 다음과 같은 요청을 보낸다.

~~~http
POST /emails HTTP/1.1
Host: api.resend.com
Authorization: Bearer re_xxxxxxxxx
Content-Type: application/json
~~~

~~~json
{
  "from": "책갈피 <no-reply@chaekgalpi.kr>",
  "to": ["teacher@example.com"],
  "subject": "책갈피 가입을 환영합니다",
  "html": "<p>책갈피 계정이 생성되었습니다.</p>"
}
~~~

메일 업체는 다음을 대신 처리한다.

- Gmail·네이버 등 수신 메일 서버와 통신
- SPF·DKIM 서명과 발송 IP 평판 관리
- 일시적인 실패 재시도
- 반송(bounce)·스팸 신고·차단 목록 관리
- 발송 기록과 webhook 제공

API의 성공 응답은 보통 **발송 요청을 접수했다**는 뜻이다. 받은편지함 도착까지 보장하는 것은 아니므로 최종 상태는 업체 대시보드나 webhook으로 확인한다.

---

## 6. 메일 서비스 비교

| 서비스                          | 무료·기본 범위(작성일 기준)        | Rails 연결                     | 장점                                 | 주의점                                |
| ------------------------------- | ---------------------------------- | ------------------------------ | ------------------------------------ | ------------------------------------- |
| **Resend**                      | 무료 월 3,000건, 일 100건          | 공식 `resend` gem              | 가장 간단한 Rails 도입, 직관적인 API | 외부 해외 SaaS, 무료 일일 한도        |
| **NAVER Cloud Outbound Mailer** | 월 1,000건 무료, 초과 0.45원/건    | HTTP API용 서비스 객체·adapter | 한국어 운영, 저렴함                  | Action Mailer용 공식 단일 설정은 아님 |
| **Amazon SES**                  | à la carte $0.10/1,000건 + 데이터  | `aws-actionmailer-ses`         | 매우 저렴하고 확장성 큼              | IAM·리전·sandbox 해제·도메인 인증     |
| **OCI Email Delivery**          | Always Free 월 3,000건             | HTTPS API 또는 SMTP            | OCI 안에서 저렴하게 통합             | OCI 인증·정책 설정이 복잡             |
| **SendGrid**                    | 플랜은 수시 변경                   | 공식 Ruby SDK·Web API          | 오래된 생태계, 상세 이벤트           | 초기 도메인·계정 심사 가능            |
| **Postmark**                    | 개발자 월 100건, 유료 10,000건부터 | 공식 라이브러리                | 트랜잭션 메일에 집중                 | 소량 무료 범위가 작음                 |

이 프로젝트의 추천:

- DigitalOcean 배포: **Resend**
- NAVER Cloud 단일 사업자 구성: **Cloud Outbound Mailer**
- AWS 단일 사업자 구성: **SES API**
- OCI 실험 구성: **OCI Email Delivery API**

클라우드 사업자와 메일 업체는 같을 필요가 없다. AWS EC2에서 Resend를 사용하거나 DigitalOcean에서 SES API를 호출해도 된다. 모두 공개 HTTPS API이기 때문이다.

---

## 7. Resend를 Rails에 붙이는 예시

현재 앱에는 이메일 컬럼이 없으므로 먼저 성인 역할의 이메일 저장 정책과 마이그레이션을 별도로 설계해야 한다.

### 7.1 도메인과 DNS

서비스 도메인:

~~~text
chaekgalpi.kr
~~~

웹 DNS:

~~~text
A  chaekgalpi.kr  → 클라우드 서버 공인 IP
~~~

발신 주소:

~~~text
책갈피 <no-reply@chaekgalpi.kr>
~~~

Resend에 도메인을 등록하면 DNS에 추가할 SPF·DKIM 레코드를 안내한다. DMARC도 함께 설정한다. 이 TXT/CNAME 레코드는 웹사이트의 A 레코드와 공존한다.

### 7.2 API 키 저장

API 키는 코드나 Git에 넣지 않고 Rails credentials에 저장한다.

~~~bash
bin/rails credentials:edit
~~~

~~~yaml
resend:
  api_key: "re_xxxxxxxxxxxxxxxxx"
~~~

프로덕션 서버에는 기존 방식대로 `RAILS_MASTER_KEY`만 주입한다.

> [!CAUTION]
> `config/master.key`는 모든 Rails credentials를 복호화한다. 절대 Git에 커밋하거나 채팅·문서·스크린샷으로 공유하지 않는다.

### 7.3 gem과 initializer

`Gemfile`:

~~~ruby
gem "resend"
~~~

설치:

~~~bash
bundle install
~~~

`config/initializers/resend.rb`:

~~~ruby
api_key = Rails.application.credentials.dig(:resend, :api_key)
Resend.api_key = api_key if api_key.present?
~~~

### 7.4 production 설정

`config/environments/production.rb`:

~~~ruby
config.action_mailer.delivery_method = :resend
config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = true

config.action_mailer.default_url_options = {
  host: ENV.fetch("APP_HOST"),
  protocol: "https"
}
~~~

`config/deploy.yml`:

~~~yaml
env:
  clear:
    APP_HOST: chaekgalpi.kr

proxy:
  ssl: true
  host: chaekgalpi.kr
~~~

### 7.5 기본 발신자

`app/mailers/application_mailer.rb`:

~~~ruby
class ApplicationMailer < ActionMailer::Base
  default from: "책갈피 <no-reply@chaekgalpi.kr>"
  layout "mailer"
end
~~~

### 7.6 실제 메일러

~~~ruby
class AccountMailer < ApplicationMailer
  def welcome
    @name = params[:name]

    mail(
      to: params[:to],
      subject: "책갈피 가입을 환영합니다"
    )
  end
end
~~~

`app/views/account_mailer/welcome.html.erb`:

~~~erb
<p><%= @name %> 선생님, 안녕하세요.</p>
<p>책갈피 계정이 생성되었습니다.</p>
<p><%= link_to "책갈피 시작하기", root_url %></p>
~~~

발송:

~~~ruby
AccountMailer.with(
  name: teacher.name,
  to: teacher.email
).welcome.deliver_later
~~~

`deliver_later`를 쓰면 웹 요청이 이메일 API 응답을 기다리지 않는다. 현재 앱의 Solid Queue가 백그라운드에서 발송하고 실패한 잡을 운영자가 확인할 수 있다.

### 7.7 테스트 순서

1. 개발 환경에서 본인 이메일 한 개로 발송
2. HTML과 text 템플릿 확인
3. 링크가 `https://chaekgalpi.kr/...`로 생성되는지 확인
4. Gmail·네이버 메일 각각 수신 확인
5. SPF·DKIM·DMARC 통과 여부 확인
6. 존재하지 않는 주소로 bounce 상태 확인
7. API 장애 시 Solid Queue 실패·재시도 확인
8. 프로덕션 로그에 API 키와 메일 본문이 남지 않는지 확인

---

## 8. 배포 전 공통 체크리스트

### 서버·네트워크

- [ ] 최소 2GB 메모리 확보
- [ ] x86/ARM에 맞게 `builder.arch` 설정
- [ ] SSH 키 로그인만 허용
- [ ] 22·80·443 외 불필요한 인바운드 차단
- [ ] 실제 도메인과 Kamal proxy SSL 연결
- [ ] 비용 예산·이상 사용 알림 설정

### 데이터

- [ ] `/rails/storage` 영속 볼륨 확인
- [ ] SQLite DB 4개가 재배포 후 유지되는지 확인
- [ ] SQLite 일일 백업과 복구 리허설
- [ ] Active Storage의 Object Storage 이전 계획 확정
- [ ] 학생 사진·음성의 저장 리전과 보존 기간 결정

### 메일

- [ ] 이메일을 수집할 역할 결정
- [ ] 앱 도메인과 발신 도메인 결정
- [ ] SPF·DKIM·DMARC 설정
- [ ] API 키를 Rails credentials에 저장
- [ ] `default_url_options.host`를 실제 앱 도메인으로 설정
- [ ] `deliver_later`와 Solid Queue 실패 상태 확인
- [ ] bounce·complaint·차단 목록 처리 정책 마련

---

## 9. 공식 참고 자료

### DigitalOcean

- [Droplet 요금](https://www.digitalocean.com/pricing/droplets)
- [리전별 제품 가용성](https://docs.digitalocean.com/platform/regional-availability/)
- [Spaces 요금](https://docs.digitalocean.com/products/spaces/details/pricing/)
- [Droplet 백업 요금](https://docs.digitalocean.com/products/backups/details/pricing/)
- [Container Registry 요금](https://docs.digitalocean.com/products/container-registry/details/pricing/)
- [SMTP 차단 정책](https://docs.digitalocean.com/support/why-is-smtp-blocked/)

### NAVER Cloud Platform

- [서비스별 공식 요금](https://www.ncloud.com/charge/price/ko)
- [VPC Server 사용 준비](https://guide.ncloud-docs.com/docs/server-spec-vpc)
- [Object Storage S3 API](https://api.ncloud-docs.com/docs/en/storage-objectstorage)
- [Cloud Outbound Mailer 개요](https://guide.ncloud-docs.com/docs/en/email-email-1-1)
- [Cloud Outbound Mailer 도메인 관리](https://guide.ncloud-docs.com/docs/en/cloudoutboundmailer-use-domain)

### AWS

- [AWS 리전 목록](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.html)
- [EC2 On-Demand 요금](https://aws.amazon.com/ec2/pricing/on-demand/)
- [EBS 요금](https://aws.amazon.com/ebs/pricing/)
- [VPC·공인 IPv4 요금](https://aws.amazon.com/vpc/pricing/)
- [S3 요금](https://aws.amazon.com/s3/pricing/)
- [SES 요금](https://aws.amazon.com/ses/pricing/)
- [SES API 발송](https://docs.aws.amazon.com/ses/latest/dg/send-email-api.html)
- [Rails Action Mailer용 SES](https://docs.aws.amazon.com/sdk-for-ruby/aws-actionmailer-ses/api/)

### Oracle Cloud Infrastructure

- [OCI 리전 목록](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm)
- [Always Free 최신 한도](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Free Tier 정책](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm)
- [네트워크 요금·월 10TB 무료](https://www.oracle.com/cloud/networking/virtual-cloud-network/pricing/)
- [Email Delivery 개요](https://docs.oracle.com/en-us/iaas/Content/Email/Concepts/overview.htm)
- [Email Delivery HTTPS 발송](https://docs.oracle.com/en/learn/send-email-with-ociemaildelivery-http/)

### 독립 메일 서비스

- [Resend Rails 연동](https://resend.com/ruby)
- [Resend 요금](https://resend.com/pricing)
- [SendGrid Web API와 SMTP 비교](https://www.twilio.com/docs/sendgrid/for-developers/sending-email/web-api-vs-smtp)
- [Postmark 요금](https://postmarkapp.com/pricing)
