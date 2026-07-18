ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

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

    # 역할별 로그인 헬퍼(통합 테스트 공용). 로그인 표면이 둘로 나뉘었다(sessions_controller):
    #   - 학생: (학교·학급·이름) 튜플 + 비밀번호 → student_login_path.
    #   - 교직원(교사·교무관리자·사서·총괄관리자): 이메일 + 비밀번호 → staff_login_path.
    # 교직원 계정에 이메일이 없으면 로그인용 합성 이메일을 즉석 부여한다(검증 우회 update_column,
    # 각 테스트 트랜잭션과 함께 롤백). 이로써 기존 테스트는 role 만 알면 표면 분리 후에도 동작한다.
    def login_as(user, password: "password")
      if user.student?
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
