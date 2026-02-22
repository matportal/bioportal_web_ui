class GroupsIoClient
  API_BASE = "https://api.groups.io"

  def initialize(api_key:)
    @api_key = api_key.to_s.strip
  end

  def invite(group_name:, emails:, subject: nil, message: nil)
    return failure("missing_api_key") if @api_key.empty?
    return failure("missing_group_name") if group_name.to_s.strip.empty?
    email_list = Array(emails).map(&:to_s).reject(&:empty?).join("\n")
    return failure("missing_emails") if email_list.empty?

    response = connection.post("/v1/invite") do |req|
      req.body = {
        group_name: group_name.to_s.strip,
        emails: email_list
      }
      req.body[:subject] = subject if subject.present?
      req.body[:message] = message if message.present?
    end

    return failure("http_#{response.status}") unless response.success?

    payload = parse_json(response.body)
    return failure("invalid_response") if payload.nil?

    if payload["object"] == "error"
      return { ok: payload["type"] == "pending_invites", error: payload["type"], payload: payload }
    end

    errors = Array(payload["errors"])
    return { ok: errors.empty? || payload["invited"].present?, error: errors, payload: payload }
  rescue => e
    failure(e.class.name)
  end

  private

  def connection
    @connection ||= Faraday.new(url: API_BASE) do |conn|
      conn.request :url_encoded
      conn.adapter Faraday.default_adapter
      conn.basic_auth(@api_key, "")
    end
  end

  def parse_json(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    nil
  end

  def failure(error)
    { ok: false, error: error }
  end
end
