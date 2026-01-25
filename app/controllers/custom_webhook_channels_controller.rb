# frozen_string_literal: true

module DiscourseCustomWebhook
  class CustomWebhookChannelsController < ::Admin::AdminController
    requires_plugin DiscourseCustomWebhook::PLUGIN_NAME

    before_action :find_channel, only: %i[show update destroy test]

    def index
      channels = CustomWebhookChannel.includes(:rules).order(:name)
      render json: { channels: serialize_data(channels, CustomWebhookChannelSerializer) }
    end

    def show
      render json: { channel: CustomWebhookChannelSerializer.new(@channel, root: false) }
    end

    def create
      channel = CustomWebhookChannel.new(channel_params)

      if channel.save
        render json: { channel: CustomWebhookChannelSerializer.new(channel, root: false) }
      else
        render json: { errors: channel.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      # Don't update webhook_secret if it's masked
      params_to_use = channel_params
      if params_to_use[:webhook_secret] == "••••••••"
        params_to_use = params_to_use.except(:webhook_secret)
      end

      if @channel.update(params_to_use)
        render json: { channel: CustomWebhookChannelSerializer.new(@channel, root: false) }
      else
        render json: { errors: @channel.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @channel.destroy!
      render json: success_json
    end

    def test
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
        DiscourseCustomWebhook.send_to_channel(@channel, post)
        render json: { success: true, message: I18n.t("custom_webhook.test.success") }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end

    private

    def find_channel
      @channel = CustomWebhookChannel.find(params[:id])
    end

    def channel_params
      params.require(:channel).permit(
        :name,
        :webhook_url,
        :webhook_secret,
        :message_content,
        :excerpt_length,
        :enabled
      )
    end
  end
end
