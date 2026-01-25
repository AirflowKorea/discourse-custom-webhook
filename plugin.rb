# frozen_string_literal: true

# name: discourse-custom-webhook
# about: Sends webhook notifications to custom endpoints when new posts are created
# version: 2.0.0
# authors: choo121600
# url: https://github.com/choo121600/discourse-custom-webhook
# required_version: 2.7.0

enabled_site_setting :custom_webhook_enabled

register_asset "stylesheets/custom-webhook-admin.scss"

module ::DiscourseCustomWebhook
  PLUGIN_NAME = "discourse-custom-webhook"

  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseCustomWebhook
  end

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

  def self.build_payload(channel, post)
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

    # Get category color
    embed_color = if category&.color.present?
      category.color.to_i(16)
    else
      5793266
    end

    # Build author info
    base_url = Discourse.base_url
    author_url = "#{base_url}/u/#{user.username}"
    avatar_url = ensure_protocol(user.small_avatar_url)

    excerpt_length = channel.excerpt_length || 400

    {
      content: channel.message_content.presence || "",
      embeds: [
        {
          title: title,
          color: embed_color,
          description: post.excerpt(excerpt_length, keep_newlines: true, keep_emoji_images: false) || "",
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

  def self.send_to_channel(channel, post)
    payload = build_payload(channel, post)

    uri = URI.parse(channel.webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"

    if channel.webhook_secret.present?
      request["X-Webhook-Secret"] = channel.webhook_secret
    end

    request.body = payload.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("[CustomWebhook] Channel '#{channel.name}' failed: #{response.code} - #{response.body}")
      raise "HTTP #{response.code}: #{response.body}"
    end

    response
  end

  def self.send_notification(post)
    return unless SiteSetting.custom_webhook_enabled
    return if post.post_type != Post.types[:regular]
    return if post.topic.blank? || post.topic.archetype == Archetype.private_message

    # Find all channels with matching rules
    matching_channels = []

    DiscourseCustomWebhook::CustomWebhookChannel.enabled.includes(:rules).find_each do |channel|
      # Check if any rule matches this post (excluding muted rules)
      matching_rule = channel.rules.ordered.find { |rule| rule.matches_post?(post) }

      if matching_rule
        matching_channels << channel
      elsif channel.rules.empty?
        # Channel with no rules = catch-all (watch all)
        matching_channels << channel
      end
    end

    return if matching_channels.empty?

    # Send to all matching channels in background threads
    matching_channels.each do |channel|
      Thread.new do
        begin
          send_to_channel(channel, post)
        rescue => e
          Rails.logger.error("[CustomWebhook] Error sending to '#{channel.name}': #{e.message}")
        end
      end
    end
  end
end

after_initialize do
  # Load models
  require_relative "app/models/custom_webhook_channel"
  require_relative "app/models/custom_webhook_rule"

  # Load serializers
  require_relative "app/serializers/custom_webhook_rule_serializer"
  require_relative "app/serializers/custom_webhook_channel_serializer"

  # Load controllers
  require_relative "app/controllers/custom_webhook_channels_controller"
  require_relative "app/controllers/custom_webhook_rules_controller"

  # Load routes
  require_relative "config/routes"

  # Register admin route
  add_admin_route "custom_webhook.title", "custom-webhook"

  # Extend AdminPluginsController to add our route
  Discourse::Application.routes.append do
    get "/admin/plugins/custom-webhook" => "admin/plugins#index", constraints: StaffConstraint.new
    get "/admin/plugins/custom-webhook/*path" => "admin/plugins#index", constraints: StaffConstraint.new
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
