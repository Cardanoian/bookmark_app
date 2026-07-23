ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "xlsx_test_helper"

# 테스트는 외부 API 를 절대 호출하지 않는다. credentials 에 실 키가 들어 있어도
# 테스트 환경에서는 외부 서비스 키를 공란으로 강제해 모든 클라이언트가 오프라인
# 폴백(도서검색→로컬 캐시, 정보나루→CSV, Gemini→규칙기반)을 타도록 만든다.
# 개별 테스트는 스텁 커넥션을 DI 로 주입해 원격 성공 경로를 검증한다.
Rails.application.credentials.tap do |creds|
  creds.instance_variable_set(:@config, creds.config.merge(
    gemini: { api_key: "" },
    naver: { client_id: "", client_secret: "" },
    data4library: { api_key: "" },
    neis: { api_key: "" }
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
