class SubscribeMailer < ApplicationMailer

    def register_for_announce_list(email,firstName,lastName)
      return unless subscription_configs_valid?

      service = $ANNOUNCE_LIST_SERVICE.to_s.upcase
      case service
      when "SYMPA"
        mail(
          :to => $ANNOUNCE_SERVICE_HOST,
          :from => email,
          :subject => "subscribe #{$ANNOUNCE_LIST} #{firstName} #{lastName}")
      when "GROUPS_IO"
        to_address = "#{$ANNOUNCE_LIST}+subscribe@#{$ANNOUNCE_SERVICE_HOST}"
        mail(
          :to => to_address,
          :from => email,
          :subject => "subscribe #{$ANNOUNCE_LIST}")
      end
    end

    def notify_announce_list_subscription(email)
      return unless support_email_present?

      mail(
        :to => $SUPPORT_EMAIL,
        :from => email,
        :subject => "#{email} has been subscribe to our user mailing list #{$ANNOUNCE_LIST}")
    end

    def unregister_for_announce_list(email)
      return unless subscription_configs_valid?

      service = $ANNOUNCE_LIST_SERVICE.to_s.upcase
      case service
      when "SYMPA"
        mail(
          :to => $ANNOUNCE_SERVICE_HOST,
          :from => email,
          :subject => "unsubscribe #{$ANNOUNCE_LIST}")
      when "GROUPS_IO"
        to_address = "#{$ANNOUNCE_LIST}+unsubscribe@#{$ANNOUNCE_SERVICE_HOST}"
        mail(
          :to => to_address,
          :from => email,
          :subject => "unsubscribe #{$ANNOUNCE_LIST}")
      end
    end

    def notify_announce_list_unsubscription(email)
      return unless support_email_present?

      mail(
        :to => $SUPPORT_EMAIL,
        :from => email,
        :subject => "#{email} has been unsubscribe from our user mailing list #{$ANNOUNCE_LIST}")
    end

    private

    def subscription_configs_valid?
      $ANNOUNCE_SERVICE_HOST.present? &&  $ANNOUNCE_LIST_SERVICE.present? && $ANNOUNCE_LIST.present?
    end

    def support_email_present?
      $SUPPORT_EMAIL.present?
    end

end
