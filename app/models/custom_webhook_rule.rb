# frozen_string_literal: true

module DiscourseCustomWebhook
  class CustomWebhookRule < ActiveRecord::Base
    self.table_name = "custom_webhook_rules"

    belongs_to :channel,
               class_name: "DiscourseCustomWebhook::CustomWebhookChannel",
               foreign_key: :custom_webhook_channel_id

    # Filter types
    # 0 = watch: all posts (topics + replies)
    # 1 = follow: first post only (new topics)
    # 2 = mute: block notifications
    enum filter: { watch: 0, follow: 1, mute: 2 }

    validates :filter, presence: true

    scope :ordered, -> { order(priority: :desc, created_at: :asc) }

    # Serialize tags as JSON
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
      when "watch"
        true
      when "follow"
        post.is_first_post?
      when "mute"
        false
      else
        true
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
end
