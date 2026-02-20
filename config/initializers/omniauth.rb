# Load env-based provider config before wiring OmniAuth.
require_relative 'omniauth_providers_env'

Rails.application.config.middleware.use OmniAuth::Builder do
  Array($OMNIAUTH_PROVIDERS).each do |provider, config|
    provider_options = { client_options: {}.merge(config[:client_options].to_h) }
    provider_options[:name] = config[:name] if config[:name].present?
    provider_options[:scope] = config[:scope] if config[:scope].present?
    provider config[:strategy] || provider, config[:client_id], config[:client_secret], provider_options
  end
end
