# frozen_string_literal: true

class CreateCustomWebhookChannels < ActiveRecord::Migration[7.0]
  def change
    create_table :custom_webhook_channels do |t|
      t.string :name, null: false
      t.string :webhook_url, null: false
      t.string :webhook_secret
      t.string :message_content
      t.integer :excerpt_length, default: 400
      t.boolean :enabled, default: true
      t.timestamps
    end

    add_index :custom_webhook_channels, :enabled
  end
end
