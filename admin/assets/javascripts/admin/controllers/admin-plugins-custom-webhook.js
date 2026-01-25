import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { A } from "@ember/array";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { cancel, debounce } from "@ember/runloop";
import I18n from "discourse-i18n";

export default class AdminPluginsCustomWebhookController extends Controller {
  @service dialog;

  @tracked editingChannel = null;
  @tracked editingRule = null;
  @tracked isNewChannel = false;
  @tracked isNewRule = false;
  @tracked testingChannel = null;
  @tracked testTopicId = "";
  @tracked testLoading = false;
  @tracked testSearchQuery = "";
  @tracked testSearchResults = [];
  @tracked testSearchLoading = false;
  @tracked testSelectedTopic = null;

  _searchDebounce = null;

  get filterOptions() {
    return [
      { id: "watch", name: I18n.t("custom_webhook.filters.watch") },
      { id: "follow", name: I18n.t("custom_webhook.filters.follow") },
      { id: "mute", name: I18n.t("custom_webhook.filters.mute") },
    ];
  }

  @action
  newChannel() {
    this.editingChannel = {
      name: "",
      webhook_url: "",
      webhook_secret: "",
      message_content: "",
      excerpt_length: 400,
      enabled: true,
    };
    this.isNewChannel = true;
  }

  @action
  editChannel(channel) {
    this.editingChannel = { ...channel };
    this.isNewChannel = false;
  }

  @action
  cancelEditChannel() {
    this.editingChannel = null;
    this.isNewChannel = false;
  }

  @action
  async saveChannel() {
    try {
      let result;
      if (this.isNewChannel) {
        result = await ajax("/admin/plugins/custom-webhook/channels", {
          type: "POST",
          data: { channel: this.editingChannel },
        });
        this.model.pushObject(result.channel);
      } else {
        result = await ajax(
          `/admin/plugins/custom-webhook/channels/${this.editingChannel.id}`,
          {
            type: "PUT",
            data: { channel: this.editingChannel },
          }
        );
        const index = this.model.findIndex(
          (c) => c.id === this.editingChannel.id
        );
        if (index > -1) {
          this.model.replace(index, 1, [result.channel]);
        }
      }
      this.editingChannel = null;
      this.isNewChannel = false;
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async deleteChannel(channel) {
    this.dialog.confirm({
      message: I18n.t("admin.custom_webhook.channels.delete_confirm"),
      didConfirm: async () => {
        try {
          await ajax(`/admin/plugins/custom-webhook/channels/${channel.id}`, {
            type: "DELETE",
          });
          this.model.removeObject(channel);
        } catch (e) {
          popupAjaxError(e);
        }
      },
    });
  }

  @action
  openTestModal(channel) {
    this.testingChannel = channel;
    this.testTopicId = "";
    this.testSearchQuery = "";
    this.testSearchResults = [];
    this.testSelectedTopic = null;
  }

  @action
  cancelTest() {
    if (this._searchDebounce) {
      cancel(this._searchDebounce);
    }
    this.testingChannel = null;
    this.testTopicId = "";
    this.testSearchQuery = "";
    this.testSearchResults = [];
    this.testSelectedTopic = null;
  }

  @action
  updateTestSearchQuery(event) {
    const value = event.target.value;
    this.testSearchQuery = value;

    // Check if it's a URL or ID
    const urlMatch = value.match(/\/t\/[^\/]+\/(\d+)/);
    if (urlMatch) {
      this.testTopicId = urlMatch[1];
      this.testSearchResults = [];
      return;
    }

    const idMatch = value.match(/^(\d+)$/);
    if (idMatch) {
      this.testTopicId = idMatch[1];
      this.testSearchResults = [];
      return;
    }

    // Otherwise, search for topics
    this.testTopicId = "";
    if (value.length >= 2) {
      this._searchDebounce = debounce(this, this._performSearch, value, 300);
    } else {
      this.testSearchResults = [];
    }
  }

  async _performSearch(query) {
    if (!query || query.length < 2) {
      this.testSearchResults = [];
      return;
    }

    this.testSearchLoading = true;
    try {
      const result = await ajax("/search.json", {
        data: { q: query },
      });

      this.testSearchResults = (result.topics || []).slice(0, 10).map((topic) => ({
        id: topic.id,
        title: topic.title,
        slug: topic.slug,
        category_id: topic.category_id,
      }));
    } catch (e) {
      this.testSearchResults = [];
    } finally {
      this.testSearchLoading = false;
    }
  }

  @action
  selectTestTopic(topic) {
    this.testSelectedTopic = topic;
    this.testTopicId = topic.id;
    this.testSearchQuery = topic.title;
    this.testSearchResults = [];
  }

  @action
  clearTestTopic() {
    this.testSelectedTopic = null;
    this.testTopicId = "";
    this.testSearchQuery = "";
    this.testSearchResults = [];
  }

  @action
  async sendTest() {
    if (!this.testingChannel) return;

    this.testLoading = true;
    try {
      const data = {};
      if (this.testTopicId) {
        data.topic_id = this.testTopicId;
      }

      const result = await ajax(
        `/admin/plugins/custom-webhook/channels/${this.testingChannel.id}/test`,
        {
          type: "POST",
          data,
        }
      );

      const message = result.topic_title
        ? I18n.t("admin.custom_webhook.channels.test_success_with_topic", {
            topic: result.topic_title,
          })
        : I18n.t("admin.custom_webhook.channels.test_success");

      this.dialog.alert(message);
      this.cancelTest();
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.testLoading = false;
    }
  }

  @action
  newRule(channel) {
    this.editingRule = {
      channel,
      data: {
        filter: "watch",
        category_id: null,
        tags: [],
        priority: 0,
      },
    };
    this.isNewRule = true;
  }

  @action
  editRule(channel, rule) {
    this.editingRule = {
      channel,
      data: {
        filter: rule.filter,
        category_id: rule.category_id,
        tags: rule.tags || [],
        priority: rule.priority || 0,
      },
      originalRule: rule,
    };
    this.isNewRule = false;
  }

  @action
  cancelEditRule() {
    this.editingRule = null;
    this.isNewRule = false;
  }

  @action
  async saveRule() {
    const { channel, data, originalRule } = this.editingRule;

    try {
      if (this.isNewRule) {
        const result = await ajax(
          `/admin/plugins/custom-webhook/channels/${channel.id}/rules`,
          {
            type: "POST",
            data: { rule: data },
          }
        );

        if (!channel.rules) {
          channel.rules = A([]);
        }
        channel.rules.pushObject(result.rule);
      } else {
        const result = await ajax(
          `/admin/plugins/custom-webhook/channels/${channel.id}/rules/${originalRule.id}`,
          {
            type: "PUT",
            data: { rule: data },
          }
        );

        const index = channel.rules.indexOf(originalRule);
        if (index > -1) {
          channel.rules.replace(index, 1, [result.rule]);
        }
      }

      this.editingRule = null;
      this.isNewRule = false;
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async deleteRule(channel, rule) {
    this.dialog.confirm({
      message: I18n.t("admin.custom_webhook.rules.delete_confirm"),
      didConfirm: async () => {
        try {
          await ajax(
            `/admin/plugins/custom-webhook/channels/${channel.id}/rules/${rule.id}`,
            {
              type: "DELETE",
            }
          );
          channel.rules.removeObject(rule);
        } catch (e) {
          popupAjaxError(e);
        }
      },
    });
  }

  @action
  updateEditingChannelField(field, event) {
    if (this.editingChannel) {
      this.editingChannel = {
        ...this.editingChannel,
        [field]: event.target ? event.target.value : event,
      };
    }
  }

  @action
  updateEditingChannelEnabled(event) {
    if (this.editingChannel) {
      this.editingChannel = {
        ...this.editingChannel,
        enabled: event.target.checked,
      };
    }
  }

  @action
  updateRuleFilter(value) {
    if (this.editingRule) {
      this.editingRule = {
        ...this.editingRule,
        data: { ...this.editingRule.data, filter: value },
      };
    }
  }

  @action
  updateRuleCategory(categoryId) {
    if (this.editingRule) {
      this.editingRule = {
        ...this.editingRule,
        data: { ...this.editingRule.data, category_id: categoryId },
      };
    }
  }

  @action
  updateRuleTags(tags) {
    if (this.editingRule) {
      this.editingRule = {
        ...this.editingRule,
        data: { ...this.editingRule.data, tags },
      };
    }
  }

  @action
  updateRulePriority(event) {
    if (this.editingRule) {
      this.editingRule = {
        ...this.editingRule,
        data: {
          ...this.editingRule.data,
          priority: parseInt(event.target.value, 10) || 0,
        },
      };
    }
  }
}
