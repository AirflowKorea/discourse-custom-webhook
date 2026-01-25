# frozen_string_literal: true

module DiscourseCustomWebhook
  class CustomWebhookChannel < ActiveRecord::Base
    self.table_name = "custom_webhook_channels"

    has_many :rules,
             class_name: "DiscourseCustomWebhook::CustomWebhookRule",
             foreign_key: :custom_webhook_channel_id,
             dependent: :destroy

    validates :name, presence: true, length: { maximum: 255 }
    validates :webhook_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
    validates :excerpt_length, numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 2000 }

    scope :enabled, -> { where(enabled: true) }

    def self.matching_post(post)
      enabled.select do |channel|
        channel.rules.any? { |rule| rule.matches_post?(post) }
      end
    end
  end
end
