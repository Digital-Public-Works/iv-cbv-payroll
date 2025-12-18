import { application } from "./application"

import AnchorScrollController from "./anchor_scroll_controller.js"
import ScrollResetController from "./scroll_reset_controller.js"
import BackButtonController from "./cbv/back_button_controller.js"
import CbvEmployerSearch from "./cbv/employer_search"
import SessionTimeoutPageController from "./cbv/sessions_timeout_controller.js"
import SessionTimeoutModalController from "./cbv/sessions_controller.js"
import HelpController from "./help"
import PollingController from "./polling_controller.js"
import LanguageController from "./language_controller.js"
import CopyLinkController from "./copy_link_controller.js"
import CbvEntryPageController from "./cbv/entry_page_controller.js"
import PreviewFormController from "./preview_form_controller.js"
import ClickTrackerController from "./click_tracker_controller.js"

application.register("anchor-scroll", AnchorScrollController)
application.register("scroll-reset", ScrollResetController)
application.register("back-button", BackButtonController)
application.register("cbv-employer-search", CbvEmployerSearch)
application.register("click-tracker", ClickTrackerController)
application.register("polling", PollingController)
application.register("session", SessionTimeoutModalController)
application.register("help", HelpController)
application.register("language", LanguageController)
application.register("copy-link", CopyLinkController)
application.register("cbv-entry-page", CbvEntryPageController)
application.register("preview-form", PreviewFormController)
application.register("session-timeout", SessionTimeoutPageController)

Turbo.StreamActions.redirect = function () {
  Turbo.visit(this.target)
}
