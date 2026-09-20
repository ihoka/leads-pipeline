class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Stopgap access control. There is no user model yet, and the deployed app
  # exposes every lead, scraped third-party evidence and AI rationale at a
  # public hostname, so production is gated behind HTTP basic auth until a real
  # auth system replaces this. It is production-only on purpose: development
  # and test need no credentials. ENV.fetch raising on a missing key is also
  # the point — a deploy that forgets the secrets must fail to boot rather than
  # come up open. The trailing .presence closes the gap ENV.fetch leaves open:
  # an exported-but-blank secret (e.g. `fly secrets set LEADS_PIPELINE_PASSWORD=`)
  # returns "" rather than raising, which would otherwise boot with a blank
  # password. Mirrors the same fix already applied to AnthropicClient#api_key.
  if Rails.env.production?
    http_basic_authenticate_with(
      name: ENV.fetch("LEADS_PIPELINE_USER").presence || raise("LEADS_PIPELINE_USER is blank"),
      password: ENV.fetch("LEADS_PIPELINE_PASSWORD").presence || raise("LEADS_PIPELINE_PASSWORD is blank")
    )
  end
end
