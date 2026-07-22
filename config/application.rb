require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module BookmarkApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # 한국 표준시(KST, UTC+9) 기준으로 시각/날짜를 판정한다. 미설정 시 Rails 는
    # Time.zone 을 UTC 로 고정하므로 Date.current 가 UTC 날짜를 반환해, 한국 자정~오전 9시
    # 사이에 "오늘 시작" 미션/챌린지가 아직 시작 안 한 것(전날)으로 오판정된다(UTC 드리프트).
    # DB 저장은 default_timezone(:utc) 유지 → 스키마 변경 불필요, 해석 기준만 KST 로 이동.
    config.time_zone = "Asia/Seoul"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
