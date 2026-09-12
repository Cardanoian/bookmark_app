require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # CHROME_BIN — 크롬이 기본 경로(/usr/bin/google-chrome 등)에 없는 개발기에서 쓸 실행 파일.
  # Selenium Manager 가 받아 둔 Chrome for Testing(~/.cache/selenium/chrome/...)을 가리키면 된다.
  # 없으면 지금까지처럼 기본 경로를 찾고, 못 찾으면 각 테스트가 스스로 skip 한다.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"].present?
  end
end
