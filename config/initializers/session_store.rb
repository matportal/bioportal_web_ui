# Be sure to restart your server when you modify this file.

# BioportalWebUi::Application.config.session_store :cookie_store, key: '_bioportal_web_ui_session'

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rails generate session_migration")
BioportalWebUi::Application.config.session_store :mem_cache_store
