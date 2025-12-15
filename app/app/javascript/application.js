// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"

import "@uswds/uswds"

// make sure USWDS components are wired to their behavior after a Turbo navigation
import components from "@uswds/uswds/src/js/components"

// Loops through USWDS components and reinitializes them on the page
// Each behavior handles the JavaScript functionality for a UI component
// See: https://github.com/uswds/uswds/blob/852076b6409e20ba95e3a589ad3cf38ca9b68442/packages/uswds-core/src/js/start.js

// Before Turbo caches the page, tear down USWDS components to restore original HTML.
// This prevents issues where components (like modals) have their IDs removed during
// initialization and would fail to reinitialize from cached HTML.
document.addEventListener("turbo:before-cache", () => {
  const target = document.body
  Object.keys(components).forEach((key) => {
    const behavior = components[key]
    if (typeof behavior.off === "function") {
      behavior.off(target)
    }
  })
})

// Reinitialize USWDS components after Turbo renders the page.
// We call off() first to handle the case where USWDS auto-initialized on import
// before turbo:render fired (e.g., initial page load).
document.addEventListener("turbo:render", () => {
  const target = document.body
  Object.keys(components).forEach((key) => {
    const behavior = components[key]
    if (typeof behavior.off === "function") {
      behavior.off(target)
    }
    behavior.on(target)
  })
})
