require "active_support/core_ext/integer/time"
require "ipaddr"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy
  # (kamal-proxy with Let's Encrypt, config/deploy.yml proxy.ssl: true).
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # 신뢰 프록시 명시 — request.remote_ip 신뢰성(로그인 fail2ban IP 스로틀 키의 근거, Phase 6 #7 후속).
  # 앱은 kamal-proxy(단일 리버스 프록시, 도커 사설 네트워크) 뒤에서만 구동되므로, 신뢰 프록시를
  # 루프백 + 사설 대역으로 **명시**해 X-Forwarded-For 로부터 실제 클라이언트 IP를 뽑는 경계를
  # 감사 가능하게 고정한다(암묵적 기본값 의존 제거). 배열을 지정하면 Rails 기본 목록을 대체하므로,
  # kamal/도커가 쓰는 사설 대역(10/8·172.16/12·192.168/16)과 루프백을 모두 포함한다.
  #   · 위조 저항: kamal-proxy 가 실제 소켓 IP를 XFF 에 덧붙이고 ip_spoofing_check(기본 on)가 켜져
  #     있어, 공인 클라이언트가 보낸 위조 XFF 로 remote_ip 를 바꿀 수 없다.
  #   · 계정축 스로틀(user.id 정규화)은 애초에 IP 위조와 무관해 표적 계정 브루트포스를 독립 차단한다.
  # 실배포 시 도커 브리지의 실제 CIDR 로 더 좁힐 수 있다(현재는 토폴로지 전 범위를 보수적으로 포함).
  config.action_dispatch.trusted_proxies = [
    IPAddr.new("127.0.0.1"),
    IPAddr.new("::1"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16")
  ].freeze

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # 메일 발송은 Resend API 로 한다(SMTP 미사용). 젬의 Railtie 가 `:resend` delivery_method 를
  # 자동 등록하고, API 키는 config/initializers/resend.rb 가 lazy 프록으로 배선한다.
  config.action_mailer.delivery_method = :resend

  # 발송 실패를 **예외로 표면화**한다. 메일은 잡(deliver_later)에서 보내므로 이 예외를 잡이
  # rescue 해 감사 로그(mail.delivery_failed / mail.domain_unverified)로 남긴다. false 로 두면
  # 도메인 미검증·쿼터 초과가 조용히 삼켜져 "메일이 안 오는데 아무 흔적도 없는" 상태가 된다.
  config.action_mailer.raise_delivery_errors = true

  # 메일 링크(비밀번호 재설정·이메일 인증)가 가리킬 앱 호스트. config/deploy.yml 의
  # `proxy.host` 와 일치해야 한다(현재 book.gbeai.net). force_ssl 환경이므로 protocol 을
  # 명시해 링크가 http 로 생성되지 않게 한다.
  # ※ 발신 도메인(gbeai.net)과 앱 호스트(book.gbeai.net)가 다른 것은 정상이다 — Resend 도메인
  #   검증은 발신 주소 기준이라 링크 호스트와 무관하다.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "book.gbeai.net"),
    protocol: "https"
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
