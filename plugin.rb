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

    def self.ensure_protocol(url)
      return nil if url.blank?
      url.start_with?("//") ? "https:#{url}" : url
    end

    def self.formatted_display_name(user)
      if user.name.present? && user.name != user.username
        "@#{user.username} (#{user.name})"
      else
        "@#{user.username}"
      end
    end

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

          if SiteSetting.custom_webhook_secret.present?
            request["X-Webhook-Secret"] = SiteSetting.custom_webhook_secret
          end

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
      category = topic.category

      # Build title with category and tags
      title_parts = [topic.title]

      if category.present?
        category_name = category.parent_category.present? ? "#{category.parent_category.name}/#{category.name}" : category.name
        title_parts << "[#{category_name}]"
      end

      tags = topic.tags.pluck(:name)
      title_parts << tags.join(", ") if tags.present?

      title = title_parts.join(" ")

      # Get category color (default to Discord blurple if no category)
      embed_color = if category&.color.present?
        category.color.to_i(16)
      else
        5793266 # Discord blurple #5865F2
      end

      # Build author info
      base_url = Discourse.base_url
      author_url = "#{base_url}/u/#{user.username}"
      avatar_url = ensure_protocol(user.small_avatar_url)

      {
        content: SiteSetting.custom_webhook_message_content.presence || "",
        embeds: [
          {
            title: title,
            color: embed_color,
            description: post.excerpt(SiteSetting.custom_webhook_excerpt_length, keep_newlines: true, keep_emoji_images: false) || "",
            url: post.full_url,
            author: {
              name: formatted_display_name(user),
              url: author_url,
              icon_url: avatar_url
            }
          }
        ]
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
