# frozen_string_literal: true

DiscourseCustomWebhook::Engine.routes.draw do
  resources :channels, controller: "custom_webhook_channels", except: [:new, :edit] do
    member do
      post :test
    end
    resources :rules, controller: "custom_webhook_rules", only: [:create, :update, :destroy]
  end
end

Discourse::Application.routes.draw do
  mount DiscourseCustomWebhook::Engine, at: "/admin/plugins/custom-webhook"
end
