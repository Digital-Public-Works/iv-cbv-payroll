import { Controller } from "@hotwired/stimulus"

/**
 * AnchorScroll Controller
 *
 * Handles smooth scrolling to anchor targets on the same page.
 * Turbo intercepts all link clicks, including hash anchors, but doesn't
 * scroll to them. This controller restores that behavior for specific links.
 *
 * ## Usage
 *
 * Add to a container with anchor links:
 *
 *   <nav data-controller="anchor-scroll">
 *     <a href="#section-1" data-action="click->anchor-scroll#scroll">Section 1</a>
 *     <a href="#section-2" data-action="click->anchor-scroll#scroll">Section 2</a>
 *   </nav>
 *
 * Or on individual links:
 *
 *   <a href="#section-1"
 *      data-controller="anchor-scroll"
 *      data-action="click->anchor-scroll#scroll">
 *     Section 1
 *   </a>
 */
export default class extends Controller {
  scroll(event) {
    const link = event.currentTarget
    const href = link.getAttribute("href")

    // Only handle hash-only links (href="#something")
    if (!href?.startsWith("#")) {
      return
    }

    const targetElement = document.querySelector(href)
    if (targetElement) {
      event.preventDefault()
      targetElement.scrollIntoView({ behavior: "smooth" })
      history.pushState(null, "", href)
    }
  }
}
