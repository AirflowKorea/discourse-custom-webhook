# frozen_string_literal: true

module DiscourseCustomWebhook
  class CustomWebhookRulesController < ::Admin::AdminController
    requires_plugin DiscourseCustomWebhook::PLUGIN_NAME

    before_action :find_channel
    before_action :find_rule, only: %i[update destroy]

    def create
      rule = @channel.rules.new(rule_params)

      if rule.save
        render json: { rule: CustomWebhookRuleSerializer.new(rule, root: false) }
      else
        render json: { errors: rule.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @rule.update(rule_params)
        render json: { rule: CustomWebhookRuleSerializer.new(@rule, root: false) }
      else
        render json: { errors: @rule.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @rule.destroy!
      render json: success_json
    end

    private

    def find_channel
      @channel = CustomWebhookChannel.find(params[:channel_id])
    end

    def find_rule
      @rule = @channel.rules.find(params[:id])
    end

    def rule_params
      permitted = params.require(:rule).permit(:filter, :category_id, :priority, tags: [])
      # Convert empty tags array or nil to empty array
      permitted[:tags] = Array(permitted[:tags]).compact_blank
      permitted
    end
  end
end
