# frozen_string_literal: true

# name: discourse-custom-webhook
# about: Sends webhook notifications to custom endpoint when new posts are created
# version: 1.0.0
# authors: choo121600
# url: https://github.com/choo121600/discourse-custom-webhook

enabled_site_setting :custom_webhook_enabled

after_initialize do
  module ::DiscourseCustomWebhook
    PLUGIN_NAME = "discourse-custom-webhook"

    def self.send_notification(post)
      return unless SiteSetting.custom_webhook_enabled
      return if SiteSetting.custom_webhook_url.blank?
      return if post.post_type != Post.types[:regular]
      return if post.topic.blank? || post.topic.archetype == Archetype.private_message

      # Category filter
      if SiteSetting.custom_webhook_categories.present?
        allowed_ids = SiteSetting.custom_webhook_categories.split("|").map(&:to_i)
        return unless allowed_ids.include?(post.topic.category_id)
      end

      payload = build_payload(post)

      Thread.new do
        begin
          uri = URI.parse(SiteSetting.custom_webhook_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 5
          http.read_timeout = 10

          request = Net::HTTP::Post.new(uri.request_uri)
          request["Content-Type"] = "application/json"
          request.body = payload.to_json

          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            Rails.logger.warn("[CustomWebhook] Failed: #{response.code} - #{response.body}")
          end
        rescue => e
          Rails.logger.error("[CustomWebhook] Error: #{e.message}")
        end
      end
    end

    def self.build_payload(post)
      topic = post.topic
      user = post.user

      {
        event: post.is_first_post? ? "topic_created" : "post_created",
        post: {
          id: post.id,
          post_number: post.post_number,
          url: post.full_url,
          raw: post.raw.truncate(SiteSetting.custom_webhook_excerpt_length),
          cooked: post.cooked.truncate(SiteSetting.custom_webhook_excerpt_length * 2),
          created_at: post.created_at.iso8601
        },
        topic: {
          id: topic.id,
          title: topic.title,
          url: topic.url,
          category_id: topic.category_id,
          category_name: topic.category&.name,
          tags: topic.tags.pluck(:name)
        },
        user: {
          id: user.id,
          username: user.username,
          name: user.name,
          avatar_url: user.small_avatar_url
        }
      }
    end
  end

  on(:post_created) do |post, opts, user|
    delay = SiteSetting.custom_webhook_delay_seconds.to_i

    if delay > 0
      Jobs.enqueue_in(delay.seconds, :custom_webhook_notify, post_id: post.id)
    else
      DiscourseCustomWebhook.send_notification(post)
    end
  end

  # Job for delayed notifications
  module Jobs
    class CustomWebhookNotify < ::Jobs::Base
      def execute(args)
        return unless args[:post_id]
        post = Post.find_by(id: args[:post_id])
        return unless post

        DiscourseCustomWebhook.send_notification(post)
      end
    end
  end
end
