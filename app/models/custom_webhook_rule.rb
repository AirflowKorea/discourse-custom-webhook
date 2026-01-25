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
    validate :category_or_tags_present

    scope :ordered, -> { order(priority: :desc, created_at: :asc) }

    def matches_post?(post)
      return false if mute?
      return false unless matches_filter?(post)
      return false unless matches_category?(post)
      return false unless matches_tags?(post)
      true
    end

    private

    def category_or_tags_present
      # Allow rules that apply to all categories and tags (catch-all rule)
      true
    end

    def matches_filter?(post)
      case filter
      when "watch"
        true  # All posts
      when "follow"
        post.is_first_post?  # Only first post (new topics)
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

      # Check if matches category or parent category
      category = Category.find_by(id: topic_category_id)
      return false unless category

      category_id == topic_category_id || category_id == category.parent_category_id
    end

    def matches_tags?(post)
      return true if tags.blank? || tags.empty?

      post_tags = post.topic&.tags&.pluck(:name) || []
      (tags & post_tags).any?
    end
  end
end
