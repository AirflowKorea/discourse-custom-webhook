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
end

after_initialize do
  # ========== MODELS ==========
  class ::DiscourseCustomWebhook::Channel < ActiveRecord::Base
    self.table_name = "custom_webhook_channels"

    has_many :rules,
             class_name: "DiscourseCustomWebhook::Rule",
             foreign_key: :custom_webhook_channel_id,
             dependent: :destroy

    validates :name, presence: true, length: { maximum: 255 }
    validates :webhook_url, presence: true
    validates :excerpt_length, numericality: { greater_than_or_equal_to: 100, less_than_or_equal_to: 2000 }

    scope :enabled, -> { where(enabled: true) }
  end

  class ::DiscourseCustomWebhook::Rule < ActiveRecord::Base
    self.table_name = "custom_webhook_rules"

    belongs_to :channel,
               class_name: "DiscourseCustomWebhook::Channel",
               foreign_key: :custom_webhook_channel_id

    enum filter: { watch: 0, follow: 1, mute: 2 }

    validates :filter, presence: true

    scope :ordered, -> { order(priority: :desc, created_at: :asc) }

    def tags
      value = read_attribute(:tags)
      return [] if value.blank?
      JSON.parse(value) rescue []
    end

    def tags=(value)
      write_attribute(:tags, Array(value).compact_blank.to_json)
    end

    def matches_post?(post)
      return false if mute?
      return false unless matches_filter?(post)
      return false unless matches_category?(post)
      return false unless matches_tags?(post)
      true
    end

    private

    def matches_filter?(post)
      case filter
      when "watch" then true
      when "follow" then post.is_first_post?
      when "mute" then false
      else true
      end
    end

    def matches_category?(post)
      return true if category_id.blank?
      topic_category_id = post.topic&.category_id
      return false if topic_category_id.blank?
      category = Category.find_by(id: topic_category_id)
      return false unless category
      category_id == topic_category_id || category_id == category.parent_category_id
    end

    def matches_tags?(post)
      tag_list = tags
      return true if tag_list.blank? || tag_list.empty?
      post_tags = post.topic&.tags&.pluck(:name) || []
      (tag_list & post_tags).any?
    end
  end

  # ========== SERIALIZERS ==========
  class ::DiscourseCustomWebhook::RuleSerializer < ApplicationSerializer
    attributes :id, :custom_webhook_channel_id, :filter, :category_id, :category_name, :tags, :priority, :created_at

    def category_name
      return nil if object.category_id.blank?
      Category.find_by(id: object.category_id)&.name
    end
  end

  class ::DiscourseCustomWebhook::ChannelSerializer < ApplicationSerializer
    attributes :id, :name, :webhook_url, :webhook_secret, :message_content, :excerpt_length, :enabled, :created_at, :updated_at

    has_many :rules, serializer: ::DiscourseCustomWebhook::RuleSerializer, embed: :objects

    def webhook_secret
      object.webhook_secret.present? ? "••••••••" : nil
    end

    def rules
      object.rules.ordered
    end
  end

  # ========== HELPER METHODS ==========
  module ::DiscourseCustomWebhook
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

      title_parts = [topic.title]
      if category.present?
        category_name = category.parent_category.present? ? "#{category.parent_category.name}/#{category.name}" : category.name
        title_parts << "[#{category_name}]"
      end
      tags = topic.tags.pluck(:name)
      title_parts << tags.join(", ") if tags.present?
      title = title_parts.join(" ")

      embed_color = category&.color.present? ? category.color.to_i(16) : 5793266

      {
        content: channel.message_content.presence || "",
        embeds: [{
          title: title,
          color: embed_color,
          description: post.excerpt(channel.excerpt_length || 400, keep_newlines: true, keep_emoji_images: false) || "",
          url: post.full_url,
          author: {
            name: formatted_display_name(user),
            url: "#{Discourse.base_url}/u/#{user.username}",
            icon_url: ensure_protocol(user.small_avatar_url)
          }
        }]
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
      request["X-Webhook-Secret"] = channel.webhook_secret if channel.webhook_secret.present?
      request.body = payload.to_json

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[CustomWebhook] Channel '#{channel.name}' failed: #{response.code}")
        raise "HTTP #{response.code}"
      end
      response
    end

    def self.send_notification(post)
      return unless SiteSetting.custom_webhook_enabled
      return if post.post_type != Post.types[:regular]
      return if post.topic.blank? || post.topic.archetype == Archetype.private_message

      Channel.enabled.includes(:rules).find_each do |channel|
        matching_rule = channel.rules.ordered.find { |rule| rule.matches_post?(post) }
        next unless matching_rule || channel.rules.empty?

        Thread.new do
          send_to_channel(channel, post)
        rescue => e
          Rails.logger.error("[CustomWebhook] Error: #{e.message}")
        end
      end
    end
  end

  # ========== CONTROLLERS ==========
  class ::DiscourseCustomWebhook::ChannelsController < ::Admin::AdminController
    requires_plugin DiscourseCustomWebhook::PLUGIN_NAME

    def index
      channels = DiscourseCustomWebhook::Channel.includes(:rules).order(:name)
      render json: { channels: channels.map { |c| DiscourseCustomWebhook::ChannelSerializer.new(c, root: false) } }
    end

    def create
      channel = DiscourseCustomWebhook::Channel.new(channel_params)
      if channel.save
        render json: { channel: DiscourseCustomWebhook::ChannelSerializer.new(channel, root: false) }
      else
        render json: { errors: channel.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      channel = DiscourseCustomWebhook::Channel.find(params[:id])
      update_params = channel_params
      update_params = update_params.except(:webhook_secret) if update_params[:webhook_secret] == "••••••••"

      if channel.update(update_params)
        render json: { channel: DiscourseCustomWebhook::ChannelSerializer.new(channel, root: false) }
      else
        render json: { errors: channel.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      DiscourseCustomWebhook::Channel.find(params[:id]).destroy!
      render json: success_json
    end

    def test
      channel = DiscourseCustomWebhook::Channel.find(params[:id])
      post = Post.where(post_type: Post.types[:regular])
                 .joins(:topic)
                 .where.not(topics: { archetype: Archetype.private_message })
                 .order(created_at: :desc)
                 .first

      if post.nil?
        render json: { error: I18n.t("custom_webhook.test.no_posts") }, status: :unprocessable_entity
        return
      end

      begin
        DiscourseCustomWebhook.send_to_channel(channel, post)
        render json: { success: true }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end

    private

    def channel_params
      params.require(:channel).permit(:name, :webhook_url, :webhook_secret, :message_content, :excerpt_length, :enabled)
    end
  end

  class ::DiscourseCustomWebhook::RulesController < ::Admin::AdminController
    requires_plugin DiscourseCustomWebhook::PLUGIN_NAME

    def create
      channel = DiscourseCustomWebhook::Channel.find(params[:channel_id])
      rule = channel.rules.new(rule_params)
      if rule.save
        render json: { rule: DiscourseCustomWebhook::RuleSerializer.new(rule, root: false) }
      else
        render json: { errors: rule.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      channel = DiscourseCustomWebhook::Channel.find(params[:channel_id])
      rule = channel.rules.find(params[:id])
      if rule.update(rule_params)
        render json: { rule: DiscourseCustomWebhook::RuleSerializer.new(rule, root: false) }
      else
        render json: { errors: rule.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      channel = DiscourseCustomWebhook::Channel.find(params[:channel_id])
      channel.rules.find(params[:id]).destroy!
      render json: success_json
    end

    private

    def rule_params
      permitted = params.require(:rule).permit(:filter, :category_id, :priority, tags: [])
      permitted[:tags] = Array(permitted[:tags]).compact_blank
      permitted
    end
  end

  # ========== ROUTES ==========
  Discourse::Application.routes.append do
    scope "/admin/plugins/custom-webhook", defaults: { format: :json } do
      resources :channels, controller: "discourse_custom_webhook/channels", only: [:index, :create, :update, :destroy] do
        member do
          post :test
        end
        resources :rules, controller: "discourse_custom_webhook/rules", only: [:create, :update, :destroy]
      end
    end
    get "/admin/plugins/custom-webhook" => "admin/plugins#index", constraints: StaffConstraint.new
    get "/admin/plugins/custom-webhook/*path" => "admin/plugins#index", constraints: StaffConstraint.new
  end

  add_admin_route "custom_webhook.title", "custom-webhook"

  # ========== EVENT HANDLER ==========
  on(:post_created) do |post, opts, user|
    delay = SiteSetting.custom_webhook_delay_seconds.to_i
    if delay > 0
      Jobs.enqueue_in(delay.seconds, :custom_webhook_notify, post_id: post.id)
    else
      DiscourseCustomWebhook.send_notification(post)
    end
  end

  # ========== BACKGROUND JOB ==========
  module ::Jobs
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
