source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# CSV parsing (전량 학교 시드 db/seeds/schools.csv). Ruby 3.4+ 부터 기본 젬에서 빠져 명시 의존.
gem "csv"

# 총괄관리자 추천도서 XLSX 업로드. 워크북 XML은 Rails 의 nokogiri, 컨테이너는 rubyzip 으로 읽는다.
gem "rubyzip", "~> 3.5"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Authorization — role-based policies [https://github.com/varvet/pundit]
gem "pundit"

# 트랜잭셔널 메일 발송(교직원 비밀번호 재설정 · 교사 가입 이메일 인증) [https://github.com/resend/resend-ruby]
# ActionMailer delivery_method `:resend` 를 Railtie 가 자동 등록한다. 내부 HTTP 는 Faraday 가
# 아니라 HTTParty(젬 의존)를 쓰므로, 앱에 HTTP 스택이 하나 더 들어오는 점을 감수한 선택이다.
gem "resend", "~> 1.6"

# HTTP client for external APIs (Gemini / Kakao / Naver / data4library) [https://github.com/lostisland/faraday]
gem "faraday"
# Retry middleware for Faraday (transient 429/503/timeout backoff) [https://github.com/lostisland/faraday-retry]
gem "faraday-retry"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
