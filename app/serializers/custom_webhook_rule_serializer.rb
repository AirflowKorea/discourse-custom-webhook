# frozen_string_literal: true

module DiscourseCustomWebhook
  class CustomWebhookRuleSerializer < ApplicationSerializer
    attributes :id,
               :custom_webhook_channel_id,
               :filter,
               :category_id,
               :category_name,
               :tags,
               :priority,
               :created_at

    def category_name
      return nil if object.category_id.blank?
      Category.find_by(id: object.category_id)&.name
    end
  end
end
