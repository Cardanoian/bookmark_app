ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "xlsx_test_helper"

# 테스트는 외부 API 를 절대 호출하지 않는다. credentials 에 실 키가 들어 있어도
# 테스트 환경에서는 외부 서비스 키를 공란으로 강제해 모든 클라이언트가 오프라인
# 폴백(도서검색→로컬 캐시, 정보나루→CSV, Claude→규칙기반·사진(OCR) 모드 비활성)을
# 타도록 만든다. 개별 테스트는 스텁 커넥션을 DI 로 주입해 원격 성공 경로를 검증한다.
#
# ⚠️ ENV 도 함께 비운다. 키 소스 규약이 **ENV 우선 → credentials 폴백**이라, credentials 만
# 스텁하면 개발자 셸에 ANTHROPIC_API_KEY 가 export 돼 있을 때 테스트가 실제
# API 를 때리고 과금까지 발생한다.
%w[ANTHROPIC_API_KEY NAVER_CLIENT_ID NAVER_CLIENT_SECRET DATA4LIBRARY_API_KEY NEIS_API_KEY].each do |name|
  ENV[name] = nil
end

Rails.application.credentials.tap do |creds|
  creds.instance_variable_set(:@config, creds.config.merge(
    anthropic: { api_key: "" },
    naver: { client_id: "", client_secret: "" },
    data4library: { api_key: "" },
    neis: { api_key: "" },
    resend: { api_key: "" }
  ))
  creds.instance_variable_set(:@options, nil)
end

# Force ActionCable to load so turbo-rails' `assert_turbo_stream_broadcasts` helper
# is reliably available. That helper is included via a nested
# `on_load(:action_cable) { on_load(:active_support_test_case) { … } }` hook, so it
# only appears once ActionCable::Server::Base loads. Left lazy, its availability
# depends on test execution order (a latent flake). Loading it here makes it
# deterministic.
ActionCable::Server::Base

# ISBN이 필수인 Book 테스트 데이터의 기본값. 개별 테스트가 ISBN 동작을 검증할 때는 명시값이
# 이 기본값을 덮어쓴다. 프로세스별 순번 + 유효 체크디지트라 병렬 테스트 DB에서도 유일하다.
module TestBookIsbn
  @sequence = 0

  def self.next
    @sequence += 1
    base = "979#{@sequence.to_s.rjust(9, "0")}" # ISBN-13의 앞 12자리
    "#{base}#{Books::Isbn.isbn13_check_digit(base)}"
  end
end

Book.attribute :isbn, :string, default: -> { TestBookIsbn.next }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include XlsxTestHelper

    # Add more helper methods to be used by all tests here...

    # Seed the full monster dex (24 lines × 3 stages = 72 forms) via the shared
    # seeder — the same code path the `monsters:seed` rake task runs. Rolled back
    # with each test's transaction; idempotent so it is safe to call in every setup.
    def seed_monster_species!
      MonsterSeeder.seed_all!
    end

    # Seed the 13 badge catalog rows (needed to grant/trigger badges).
    def seed_badges!
      Badge::KEYS.each do |key|
        Badge.find_or_create_by!(key: key) { |badge| badge.name = key }
      end
    end

    # **지금 제출의 첨삭이 완성된 제출 글**(Report#review_ready?)의 속성(BUG_FIX_PLAN F2·F3). 승인·학생 공개를
    # 다루는 테스트는 버전 컬럼 기본값(review_version 0 · completed_review_version NULL)에 기대지 않고 이것을
    # 쓴다 — 기본값으로는 review_ready? 가 거짓이라 승인할 수 없고 승인된 첨삭도 학생에게 숨는다.
    #   Report.create!(user:, classroom:, book_title: "책", **review_ready_attributes)                  # 검토 대기
    #   Report.create!(..., **review_ready_attributes(reviewed: true, reviewed_at: Time.current))      # 승인됨
    # rubric·level·avg 등은 넘긴 값이 기본값을 덮는다.
    REVIEW_READY_RUBRIC = {
      "content" => 3, "emotion" => 3, "life" => 3, "structure" => 3, "spelling" => 3,
      "praise" => [ "줄거리를 차례대로 잘 정리했어요." ], "fix" => [ "느낀 점을 한 문장 더 써 보세요." ],
      "grow" => [ { "text" => "책 속 인물의 마음을 떠올려 보세요.", "standard_code" => "" } ]
    }.freeze

    def review_ready_attributes(**overrides)
      { ai_status: :done, submitted_at: Time.current, review_version: 1, completed_review_version: 1,
        rubric: REVIEW_READY_RUBRIC.deep_dup }.merge(overrides)
    end

    # 제출 버전이 있는 AiReviewJob 을 그 글의 **현재 버전**으로 바로 돌린다(제출 → 첨삭 완료 흉내).
    def perform_ai_review(report)
      AiReviewJob.perform_now(report, expected_review_version: report.reload.review_version)
    end

    # 첨삭 잡을 돌리지 않고 "지금 제출의 첨삭이 끝난" 상태로만 만든다(**첨삭 포인트 적립 없음**) —
    # 미션·챌린지처럼 보상 액수를 정확히 세는 테스트가 첨삭 보상과 섞이지 않게 할 때 쓴다.
    def mark_review_ready!(report)
      report.reload.update_columns(ai_status: Report.ai_statuses[:done], rubric: REVIEW_READY_RUBRIC.deep_dup,
                                   completed_review_version: report.review_version)
    end

    # 통합 테스트(담임으로 로그인한 상태): 검토 화면의 승인 버튼처럼 **그 글의 현재 제출 버전**을 실어 승인한다.
    # HTTP 로 제출한 글은 먼저 perform_ai_review 로 첨삭을 끝내야 승인된다(완성된 첨삭만 승인 — F3).
    def approve_as_teacher(report)
      post approve_teacher_review_path(report), params: { review_version: report.reload.review_version }
    end

    # ISBN 필수 DB 제약 도입 전 레거시 중복 정리기의 회귀 테스트 전용. CHECK만 잠시 무시하고
    # 모델 콜백/검증을 우회해 과거 형식(하이픈·공란) 행을 재현한다. NOT NULL은 그대로 유지한다.
    def create_legacy_book!(title:, isbn:, category: :recommended, **attributes)
      connection = Book.connection
      connection.execute("PRAGMA ignore_check_constraints = ON")
      result = Book.insert_all!([ {
        title: title,
        isbn: isbn,
        category: Book.categories.fetch(category.to_s),
        created_at: Time.current,
        updated_at: Time.current
      }.merge(attributes) ], returning: %w[id])
      Book.find(result.rows.first.first)
    ensure
      connection&.execute("PRAGMA ignore_check_constraints = OFF")
    end

    # 메일 발송이 가능한 환경을 블록 안에서만 흉내낸다. 위 credentials 스텁이 resend 키를 비워
    # 두므로 기본값은 "발송 불가"(= 이메일 인증 게이트 비활성)이고, 게이트가 **작동하는** 경로를
    # 검증하려는 테스트만 이 헬퍼로 감싼다.
    #
    # 모듈 함수 스텁 대신 ENV 를 쓰는 이유: minitest 6 에서 `minitest/mock`(Object#stub)이 빠졌고,
    # `ResendGateway.api_key` 가 **ENV 우선 → credentials 폴백**이라 ENV 주입이 곧 실제 코드
    # 경로 검증이 된다(리포의 키 소스 규약 자체를 함께 검증). 병렬 테스트는 프로세스 단위로
    # 갈라지고 프로세스 안에서는 테스트가 순차 실행되므로 ensure 복원으로 격리가 충분하다.
    def with_mail_delivery_available
      original = ENV["RESEND_API_KEY"]
      ENV["RESEND_API_KEY"] = "re_test_only_not_a_real_key"
      yield
    ensure
      ENV["RESEND_API_KEY"] = original
    end

    # Claude 키가 설정된 상태(`Ai::ClaudeClient#configured?`)로 화면을 렌더한다 — 학생 화면의 AI 사용
    # 고지(ai_assisted_for?)처럼 **키 유무만 보는** 표시 분기 검증용. 가짜 키라 실제 호출은 인증 오류로
    # 끝나지만, 잡을 실행(perform_enqueued_jobs)하는 테스트는 이 헬퍼로 감싸지 않는다.
    def with_claude_key_configured
      original = ENV["ANTHROPIC_API_KEY"]
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test-only-not-a-real-key"
      yield
    ensure
      ENV["ANTHROPIC_API_KEY"] = original
    end

    # 역할별 로그인 헬퍼(통합 테스트 공용). 로그인 표면이 둘로 나뉘었다(sessions_controller):
    #   - 학생: (학교·학급·이름) 튜플 + 비밀번호 → student_login_path.
    #   - 교직원(교사·교무관리자·사서·총괄관리자): 이메일 + 비밀번호 → staff_login_path.
    # 교직원 계정에 이메일이 없으면 로그인용 합성 이메일을 즉석 부여한다(검증 우회 update_column,
    # 각 테스트 트랜잭션과 함께 롤백). 이로써 기존 테스트는 role 만 알면 표면 분리 후에도 동작한다.
    def login_as(user, password: "password", onboarded: true)
      if user.student?
        if onboarded && user.nickname.blank?
          user.update_columns(nickname: "테스트#{user.id}", ranking_opted_in: true)
        end
        post student_login_path, params: {
          school_id: user.school_id, classroom_id: user.classroom_id,
          name: user.name, password: password
        }
      else
        user.update_column(:email, "user#{user.id}@test.local") if user.email.blank?
        post staff_login_path, params: { email: user.email, password: password }
      end
    end
  end
end
