# Configure OmniAuth providers from environment variables when not set by config/bioportal_config_*.rb
if !defined?($OMNIAUTH_PROVIDERS) || $OMNIAUTH_PROVIDERS.nil?
  $OMNIAUTH_PROVIDERS = {}
end

def merge_omniauth_provider(key, config)
  existing = $OMNIAUTH_PROVIDERS[key] || {}
  $OMNIAUTH_PROVIDERS[key] = existing.merge(config)
end

github_client_id = ENV['GITHUB_CLIENT_ID']
github_client_secret = ENV['GITHUB_CLIENT_SECRET']
if [github_client_id, github_client_secret].all?(&:present?)
  merge_omniauth_provider(:github, {
    client_id: github_client_id,
    client_secret: github_client_secret,
    icon: $OMNIAUTH_PROVIDERS.dig(:github, :icon) || 'github.svg',
    enable: ENV.fetch('GITHUB_ENABLED', 'true').to_s.downcase == 'true'
  })
end

google_client_id = ENV['GOOGLE_CLIENT_ID']
google_client_secret = ENV['GOOGLE_CLIENT_SECRET']
if [google_client_id, google_client_secret].all?(&:present?)
  merge_omniauth_provider(:google, {
    strategy: :google_oauth2,
    client_id: google_client_id,
    client_secret: google_client_secret,
    icon: $OMNIAUTH_PROVIDERS.dig(:google, :icon) || 'google.svg',
    enable: ENV.fetch('GOOGLE_ENABLED', 'true').to_s.downcase == 'true'
  })
end

keycloak_site = ENV['KEYCLOAK_SITE']
keycloak_realm = ENV['KEYCLOAK_REALM']
keycloak_client_id = ENV['KEYCLOAK_CLIENT_ID']
keycloak_client_secret = ENV['KEYCLOAK_CLIENT_SECRET']

if [keycloak_site, keycloak_realm, keycloak_client_id, keycloak_client_secret].all?(&:present?)
  merge_omniauth_provider(:keycloak, {
    strategy: :keycloak_openid,
    client_id: keycloak_client_id,
    client_secret: keycloak_client_secret,
    client_options: { site: keycloak_site, realm: keycloak_realm },
    label: ENV['KEYCLOAK_LABEL'] || 'Keycloak',
    enable: ENV.fetch('KEYCLOAK_ENABLED', 'true').to_s.downcase == 'true'
  })
end
