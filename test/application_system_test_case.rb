require "test_helper"

# This machine has chromium/chromedriver installed rather than google-chrome,
# so Selenium Manager needs to be told explicitly where the browser binary is.
Selenium::WebDriver::Chrome.path = "/usr/bin/chromium" if File.exist?("/usr/bin/chromium")

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
end
