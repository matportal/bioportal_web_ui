class AnnounceListService
  def self.subscribe(email, first_name = nil, last_name = nil)
    return false if email.to_s.strip.empty?

    service = announce_list_service
    success = case service
              when "GROUPS_IO"
                subscribe_groups_io(email, first_name, last_name)
              when "SYMPA"
                SubscribeMailer.register_for_announce_list(email, first_name, last_name)&.deliver
                true
              else
                false
              end

    if success
      SubscribeMailer.notify_announce_list_subscription(email)&.deliver
    end

    success
  end

  private

  def self.subscribe_groups_io(email, first_name, last_name)
    api_key = groups_io_api_key
    list_name = announce_list_name
    return false if api_key.empty? || list_name.empty?

    display_name = [first_name, last_name].compact.join(" ").strip
    invitee = display_name.empty? ? email : "#{display_name} <#{email}>"

    result = GroupsIoClient.new(api_key: api_key).invite(
      group_name: list_name,
      emails: [invitee]
    )

    if result[:ok]
      true
    else
      Rails.logger.warn("Groups.io invite failed: #{result[:error]}")
      false
    end
  end

  def self.announce_list_service
    ENV["ANNOUNCE_LIST_SERVICE"].presence || (defined?($ANNOUNCE_LIST_SERVICE) ? $ANNOUNCE_LIST_SERVICE : "")
  end

  def self.announce_list_name
    ENV["ANNOUNCE_LIST"].presence || (defined?($ANNOUNCE_LIST) ? $ANNOUNCE_LIST : "")
  end

  def self.groups_io_api_key
    ENV["ANNOUNCE_GROUPS_IO_API_KEY"].to_s.strip
  end
end
