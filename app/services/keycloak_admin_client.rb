# frozen_string_literal: true

require 'faraday'
require 'json'

class KeycloakAdminClient
  def initialize
    @site = ENV['KEYCLOAK_SITE'].to_s.strip
    @realm = ENV['KEYCLOAK_REALM'].to_s.strip
    @client_id = ENV['KEYCLOAK_ADMIN_CLIENT_ID'].to_s.strip
    @client_secret = ENV['KEYCLOAK_ADMIN_CLIENT_SECRET'].to_s.strip
    @admin_realm = ENV.fetch('KEYCLOAK_ADMIN_REALM', @realm).to_s.strip
  end

  def enabled?
    [@site, @realm, @client_id, @client_secret].all? { |v| !v.empty? }
  end

  def ensure_password_reset_email(username, email)
    return :skipped unless enabled?

    user = find_user(username, email)
    if user.nil?
      user_id = create_user(username, email)
      set_required_action(user_id)
      mark_migration_flag(user_id)
      send_execute_actions_email(user_id)
      return :email_sent
    end

    user_id = user['id']
    attrs = user['attributes'] || {}
    if attrs['legacy_reset_sent']&.include?('true')
      return :already_sent
    end

    set_required_action(user_id)
    mark_migration_flag(user_id)
    send_execute_actions_email(user_id)
    :email_sent
  end

  private

  def find_user(username, email)
    user = find_user_by('username', username)
    return user if user
    find_user_by('email', email)
  end

  def find_user_by(field, value)
    return nil if value.to_s.strip.empty?
    users = get_json("/admin/realms/#{@realm}/users?#{field}=#{CGI.escape(value)}")
    users.is_a?(Array) ? users.first : nil
  end

  def create_user(username, email)
    payload = {
      username: username,
      email: email,
      enabled: true
    }
    response = admin_conn.post("/admin/realms/#{@realm}/users", JSON.dump(payload))
    if response.status == 201
      location = response.headers['location'] || response.headers['Location']
      return location.to_s.split('/').last if location
    end
    raise "Keycloak create user failed: #{response.status} #{response.body}"
  end

  def set_required_action(user_id)
    payload = { requiredActions: ['UPDATE_PASSWORD'] }
    admin_conn.put("/admin/realms/#{@realm}/users/#{user_id}", JSON.dump(payload))
  end

  def mark_migration_flag(user_id)
    payload = { attributes: { 'legacy_reset_sent' => ['true'] } }
    admin_conn.put("/admin/realms/#{@realm}/users/#{user_id}", JSON.dump(payload))
  end

  def send_execute_actions_email(user_id)
    actions = ['UPDATE_PASSWORD']
    admin_conn.put("/admin/realms/#{@realm}/users/#{user_id}/execute-actions-email", JSON.dump(actions))
  end

  def token
    @token ||= begin
      response = Faraday.post("#{@site}/realms/#{@admin_realm}/protocol/openid-connect/token") do |req|
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = URI.encode_www_form(
          grant_type: 'client_credentials',
          client_id: @client_id,
          client_secret: @client_secret
        )
      end
      raise "Keycloak token request failed: #{response.status} #{response.body}" unless response.status == 200

      JSON.parse(response.body).fetch('access_token')
    end
  end

  def admin_conn
    @admin_conn ||= Faraday.new(url: @site) do |conn|
      conn.headers['Authorization'] = "Bearer #{token}"
      conn.headers['Content-Type'] = 'application/json'
      conn.headers['Accept'] = 'application/json'
      conn.options.timeout = 10
    end
  end

  def get_json(path)
    response = admin_conn.get(path)
    return [] if response.status == 404
    raise "Keycloak admin query failed: #{response.status} #{response.body}" unless response.status.between?(200, 299)
    JSON.parse(response.body)
  end
end
