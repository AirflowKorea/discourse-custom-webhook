# frozen_string_literal: true

class CreateCustomWebhookRules < ActiveRecord::Migration[7.0]
  def change
    create_table :custom_webhook_rules do |t|
      t.references :custom_webhook_channel, null: false, foreign_key: { on_delete: :cascade }
      t.integer :filter, default: 0, null: false  # 0: watch (all), 1: follow (first post only)
      t.integer :category_id
      t.string :tags, array: true, default: []
      t.integer :priority, default: 0
      t.timestamps
    end

    add_index :custom_webhook_rules, :category_id
    add_index :custom_webhook_rules, :filter
    add_index :custom_webhook_rules, :priority
  end
end
