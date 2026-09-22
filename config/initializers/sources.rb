Rails.application.config.to_prepare do
  Sources::Registry.load_defaults!
end
