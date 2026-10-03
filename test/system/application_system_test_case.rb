require "test_helper"
require "capybara/cuprite"

# Drive system tests with Cuprite (Chrome DevTools Protocol via Ferrum) instead
# of Selenium, so no chromedriver/selenium-manager provisioning is required.
#
# Chrome binary resolution order:
#   1. CUPRITE_CHROME_PATH env var (explicit override)
#   2. A Playwright-managed Chromium under ~/.cache/ms-playwright (local dev)
#   3. Ferrum's own auto-detection of a system Chrome/Chromium (browser_path nil)
CHROME_PATH = ENV["CUPRITE_CHROME_PATH"].presence ||
  Dir[File.expand_path("~/.cache/ms-playwright/chromium-*/chrome-linux/chrome")].max

# Pages load felt-css from its CDN. Chrome ignores HTTPS_PROXY, so hand it over
# where outbound traffic has to go through one (cloud sessions); the app server
# on loopback stays direct.
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
