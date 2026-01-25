# frozen_string_literal: true

module DiscourseCustomWebhook
  class CustomWebhookChannelSerializer < ApplicationSerializer
    attributes :id,
               :name,
               :webhook_url,
               :webhook_secret,
               :message_content,
               :excerpt_length,
               :enabled,
               :created_at,
               :updated_at

    has_many :rules, serializer: CustomWebhookRuleSerializer, embed: :objects

    def webhook_secret
      object.webhook_secret.present? ? "••••••••" : nil
    end

    def rules
      object.rules.ordered
    end
  end
end
