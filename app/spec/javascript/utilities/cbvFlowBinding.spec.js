import { describe, beforeAll, afterAll, beforeEach, afterEach, it, expect, vi } from "vitest"
import { JSDOM } from "jsdom"
import {
  CBV_FLOW_HEADER,
  CBV_FLOW_PARAM,
  addCbvFlowField,
  cbvFlowHeaders,
  renderedFromHistory,
  switchedPagePath,
  currentCbvFlowId,
  installCbvFlowBinding,
} from "@js/utilities/cbvFlowBinding"

const setFlowMeta = (id) => {
  document.head.querySelector('meta[name="cbv-flow-id"]')?.remove()
  if (id === null) return
  const meta = document.createElement("meta")
  meta.name = "cbv-flow-id"
  meta.content = id
  document.head.appendChild(meta)
}

describe("cbvFlowBinding", () => {
  // test_setup.js's window is about:blank, which has no origin to resolve
  // URLs against; use a page on a partner's site, as in a browser.
  const original = { window: global.window, document: global.document }

  beforeAll(() => {
    const dom = new JSDOM("<!doctype html><html><head></head><body></body></html>", {
      url: "https://sandbox.verifymyincome.org/cbv/entry",
    })
    global.window = dom.window
    global.document = dom.window.document
  })

  afterAll(() => {
    global.window = original.window
    global.document = original.document
  })

  afterEach(() => setFlowMeta(null))

  describe("cbvFlowHeaders", () => {
    beforeEach(() => setFlowMeta("42"))

    it("reads the flow the page was rendered for", () => {
      expect(currentCbvFlowId()).toBe("42")
    })

    it("sends the page's flow on requests within the site", () => {
      expect(cbvFlowHeaders("/cbv/summary")).toEqual({ [CBV_FLOW_HEADER]: "42" })
      expect(cbvFlowHeaders()).toEqual({ [CBV_FLOW_HEADER]: "42" })
    })

    it("sends nothing on a page without a flow", () => {
      setFlowMeta(null)
      expect(cbvFlowHeaders("/cbv/summary")).toEqual({})
    })

    it("sends nothing to other sites", () => {
      expect(cbvFlowHeaders("https://example.com/cbv/summary")).toEqual({})
    })

    // Opening a link starts a new flow; the old page's flow must not follow it
    // (or the redirects after it) or the new flow would be refused.
    it("sends nothing on links that start a new flow", () => {
      expect(cbvFlowHeaders("/start")).toEqual({})
      expect(cbvFlowHeaders("/es/start?origin=sms")).toEqual({})
      expect(cbvFlowHeaders("/start/abc123")).toEqual({})
      expect(cbvFlowHeaders("/en/start/abc123")).toEqual({})
      expect(cbvFlowHeaders("/cbv/entry?token=abc123")).toEqual({})
    })

    it("still sends it on paths that only look similar", () => {
      expect(cbvFlowHeaders("/cbv/started")).toEqual({ [CBV_FLOW_HEADER]: "42" })
    })
  })

  describe("addCbvFlowField", () => {
    it("adds the page's flow to a form once, as a hidden field", () => {
      setFlowMeta("5")
      const form = document.createElement("form")

      addCbvFlowField(form)
      addCbvFlowField(form)

      const fields = form.querySelectorAll(`input[name="${CBV_FLOW_PARAM}"]`)
      expect(fields).toHaveLength(1)
      expect(fields[0].type).toBe("hidden")
      expect(fields[0].value).toBe("5")
    })

    it("adds nothing on a page without a flow", () => {
      const form = document.createElement("form")

      addCbvFlowField(form)

      expect(form.querySelector("input")).toBeNull()
    })
  })

  describe("switchedPagePath", () => {
    afterEach(() => document.documentElement.removeAttribute("lang"))

    it("keeps the page's language", () => {
      document.documentElement.lang = "es"
      expect(switchedPagePath()).toBe("/es/cbv/session/switched")
    })

    it("falls back to the default language's path", () => {
      expect(switchedPagePath()).toBe("/cbv/session/switched")
    })
  })

  describe("installCbvFlowBinding", () => {
    beforeAll(() => installCbvFlowBinding())

    it("adds the header to Turbo requests", () => {
      setFlowMeta("7")
      const fetchOptions = { headers: { Accept: "text/html" } }
      document.dispatchEvent(
        new window.CustomEvent("turbo:before-fetch-request", {
          detail: { fetchOptions, url: new URL("/cbv/summary", window.location.href) },
        })
      )

      expect(fetchOptions.headers).toEqual({ Accept: "text/html", [CBV_FLOW_HEADER]: "7" })
    })

    it("knows when the page was put back by Back/Forward", () => {
      const visit = (action) =>
        document.dispatchEvent(new window.CustomEvent("turbo:visit", { detail: { action } }))

      visit("restore")
      expect(renderedFromHistory()).toBe(true)

      visit("advance")
      expect(renderedFromHistory()).toBe(false)
    })

    it("turns a refused frame load into a page visit", () => {
      const visit = vi.fn()
      const response = { url: `${window.location.origin}/en/cbv/session/switched` }
      const event = new window.CustomEvent("turbo:frame-missing", {
        cancelable: true,
        detail: { response, visit },
      })
      document.dispatchEvent(event)

      expect(event.defaultPrevented).toBe(true)
      expect(visit).toHaveBeenCalledWith(response)
    })

    it("leaves other missing frames to Turbo", () => {
      const visit = vi.fn()
      const event = new window.CustomEvent("turbo:frame-missing", {
        cancelable: true,
        detail: { response: { url: `${window.location.origin}/cbv/summary` }, visit },
      })
      document.dispatchEvent(event)

      expect(event.defaultPrevented).toBe(false)
      expect(visit).not.toHaveBeenCalled()
    })
  })
})
