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
  # 요청은 Cloudflare → kamal-proxy → Rails 순으로 들어오므로 루프백·도커 사설 대역과 Cloudflare
  # 공식 IPv4/IPv6 대역만 신뢰한다. 배열을 지정하면 Rails 기본 목록을 대체한다.
  # Cloudflare 대역 출처: https://www.cloudflare.com/ips/
  #   · 위조 저항: 가장 가까운 비신뢰 IP가 실제 클라이언트로 선택되므로, 직접 접속한 공인 클라이언트가
  #     임의 XFF를 보내도 자신의 소켓 IP를 건너뛸 수 없다.
  #   · 계정축 스로틀(user.id 정규화)은 애초에 IP 위조와 무관해 표적 계정 브루트포스를 독립 차단한다.
  # 도커 사설 대역은 실배포 브리지의 실제 CIDR 로 더 좁힐 수 있다.
  config.action_dispatch.trusted_proxies = [
    IPAddr.new("127.0.0.1"),
    IPAddr.new("::1"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("173.245.48.0/20"),
    IPAddr.new("103.21.244.0/22"),
    IPAddr.new("103.22.200.0/22"),
    IPAddr.new("103.31.4.0/22"),
    IPAddr.new("141.101.64.0/18"),
    IPAddr.new("108.162.192.0/18"),
    IPAddr.new("190.93.240.0/20"),
    IPAddr.new("188.114.96.0/20"),
    IPAddr.new("197.234.240.0/22"),
    IPAddr.new("198.41.128.0/17"),
    IPAddr.new("162.158.0.0/15"),
    IPAddr.new("104.16.0.0/13"),
    IPAddr.new("104.24.0.0/14"),
    IPAddr.new("172.64.0.0/13"),
    IPAddr.new("131.0.72.0/22"),
    IPAddr.new("2400:cb00::/32"),
    IPAddr.new("2606:4700::/32"),
    IPAddr.new("2803:f800::/32"),
    IPAddr.new("2405:b500::/32"),
    IPAddr.new("2405:8100::/32"),
    IPAddr.new("2a06:98c0::/29"),
    IPAddr.new("2c0f:f248::/32")
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
  # `proxy.hosts`의 기본 호스트와 일치해야 한다(현재 chaekgalpi.net). force_ssl 환경이므로 protocol 을
  # 명시해 링크가 http 로 생성되지 않게 한다.
  # 발신 주소도 Resend 에서 검증한 chaekgalpi.net 도메인을 사용한다.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "chaekgalpi.net"),
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
