require "test_helper"
require "capybara/cuprite"

CHROME_PATH = ENV["CUPRITE_CHROME_PATH"].presence ||
  Dir[File.expand_path("~/.cache/ms-playwright/chromium-*/chrome-linux/chrome")].max

# Chrome ignores HTTPS_PROXY, so hand it over (cloud sessions); the loopback app server stays direct.
BROWSER_OPTIONS = { "no-sandbox": nil }.merge(
  ENV["HTTPS_PROXY"].present? ? { "proxy-server": ENV["HTTPS_PROXY"] } : {}
)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite, screen_size: [ 1400, 1400 ], options: {
    browser_path: CHROME_PATH,
    browser_options: BROWSER_OPTIONS,
    headless: true,
    process_timeout: 30,
    timeout: 30
  }
end
