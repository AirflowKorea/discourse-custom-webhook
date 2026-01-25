import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsCustomWebhookRoute extends DiscourseRoute {
  async model() {
    const result = await ajax("/admin/plugins/custom-webhook/channels");
    return result.channels || [];
  }

  setupController(controller, model) {
    controller.set("model", model);
  }
}
