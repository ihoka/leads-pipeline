require "test_helper"

# Selenium Manager finds the browser on its own, and where a properly installed
# Google Chrome exists -- as on CI -- that is the one to use. Machines carrying
# only Chromium need to be pointed at it explicitly, so fall back to Chromium
# only once Chrome has been ruled out, and let CHROME_BINARY override both.
#
# The fallback has to stay conditional. CI has *both*: a packaged Chrome and a
# /usr/bin/chromium symlink into an unpacked Chromium snapshot that ships no
# setuid sandbox helper. Preferring that symlink whenever it existed sent CI to
# the snapshot, which exits immediately on launch and failed every system test
# at session creation.
chrome_on_path = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
  %w[google-chrome google-chrome-stable chrome].any? do |name|
    File.executable?(File.join(dir, name))
  end
end

if (override = ENV["CHROME_BINARY"].presence)
  Selenium::WebDriver::Chrome.path = override
elsif !chrome_on_path && File.executable?("/usr/bin/chromium")
  Selenium::WebDriver::Chrome.path = "/usr/bin/chromium"
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
end
