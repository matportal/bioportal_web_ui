# Be sure to restart your server when you modify this file.

# BioportalWebUi::Application.config.session_store :cookie_store, key: '_bioportal_web_ui_session'

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rails generate session_migration")
session_options = {}
cookie_domain = ENV['SESSION_COOKIE_DOMAIN'].to_s.strip
session_options[:domain] = cookie_domain unless cookie_domain.empty?
same_site = ENV['SESSION_COOKIE_SAMESITE'].to_s.strip
session_options[:same_site] = same_site.to_sym unless same_site.empty?
secure_flag = ENV['SESSION_COOKIE_SECURE'].to_s.strip
if !secure_flag.empty?
  session_options[:secure] = secure_flag.downcase == 'true'
end

BioportalWebUi::Application.config.session_store ActionDispatch::Session::CacheStore, **session_options
