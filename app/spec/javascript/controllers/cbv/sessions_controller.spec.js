import { vi, describe, beforeEach, afterEach, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import SessionController from "@js/controllers/cbv/sessions_controller.js"

vi.mock("@js/utilities/api", () => ({
  trackUserAction: vi.fn(),
}))
import { trackUserAction } from "@js/utilities/api"

vi.mock("@js/utilities/cbvFlowBinding", async () => ({
  ...(await vi.importActual("@js/utilities/cbvFlowBinding")),
  goToSwitchedPage: vi.fn(),
  navigateTo: vi.fn(),
  renderedFromHistory: vi.fn(() => false),
}))
import { goToSwitchedPage, navigateTo, renderedFromHistory } from "@js/utilities/cbvFlowBinding"

const TIMEOUT_PATH = "/cbv/session/end?timeout=true"

// test_setup.js's window is about:blank, where localStorage throws; stand in
// for the browser's storage.
const storage = new Map()
Object.defineProperty(window, "localStorage", {
  configurable: true,
  value: {
    getItem: (key) => (storage.has(key) ? storage.get(key) : null),
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: (key) => storage.delete(key),
  },
})

// The flow this page was rendered for (layouts/application's cbv-flow-id tag).
function setFlowMeta(flowId) {
  document.head.querySelector('meta[name="cbv-flow-id"]')?.remove()
  if (flowId === null) return
  const meta = document.createElement("meta")
  meta.name = "cbv-flow-id"
  meta.content = flowId
  document.head.appendChild(meta)
}

function setupDOM(timeoutSeconds = 600) {
  setFlowMeta("1")
  document.body.innerHTML = `
    <div id="session-timeout-modal" data-controller="session" data-session-target="modal" data-item-timeout-param="${timeoutSeconds}">
      <form id="extend-session-form">
        <button id="extend-session-button" data-close-modal="true" type="submit" data-action="session#trackExtend"></button>
        <a class="usa-button usa-button--outline" data-close-modal="true" data-turbo="false" data-action="session#trackEnd session#resetTimers" id="end-session-button" href="/en/cbv/session/end">End session</a>
      </form>
    </div>
    <button id="open-session-modal-button"></button>
  `
}

describe("cbv/sessions_controller", () => {
  let application

  beforeEach(() => {
    setupDOM(600)
    application = Application.start()
    application.register("session", SessionController)
    vi.useFakeTimers()
  })

  afterEach(async () => {
    vi.useRealTimers()
    // Remove the controller's element first so Stimulus disconnects it (and its
    // timers and storage listener): application.stop() alone leaves connected
    // controllers running into the next test.
    document.body.innerHTML = ""
    await new Promise((resolve) => setTimeout(resolve, 0))
    application?.stop()
    setFlowMeta(null)
    window.localStorage.removeItem("cbv-session-activity")
    vi.resetAllMocks()
  })

  it("tracks ApplicantWarnedAboutTimeout when warning timer fires", async () => {
    vi.advanceTimersByTime(300 * 1000)
    expect(trackUserAction).toHaveBeenCalledWith("ApplicantWarnedAboutTimeout")
  })

  it("goes to the timeout endpoint when the timer runs out", async () => {
    vi.advanceTimersByTime(600 * 1000)
    expect(navigateTo).toHaveBeenCalledWith(TIMEOUT_PATH)
  })

  // Sessions#end records it, and only if it really ends the session (it won't
  // while another tab is in use).
  it("leaves recording ApplicantTimedOut to the server", async () => {
    vi.advanceTimersByTime(600 * 1000)
    expect(trackUserAction).not.toHaveBeenCalledWith("ApplicantTimedOut")
  })

  it("keeps the page's language when it times out", async () => {
    document.documentElement.lang = "es"
    try {
      vi.advanceTimersByTime(600 * 1000)
      expect(navigateTo).toHaveBeenCalledWith(`/es${TIMEOUT_PATH}`)
    } finally {
      document.documentElement.removeAttribute("lang")
    }
  })

  it("tracks ApplicantExtendedSession on extend button click", async () => {
    const extendButton = document.getElementById("extend-session-button")
    extendButton.click()
    expect(trackUserAction).toHaveBeenCalledWith("ApplicantExtendedSession")
  })

  // Tabs share one session: activity in one restarts the others' countdowns,
  // and a tab whose flow the session no longer holds leaves.
  describe("across tabs", () => {
    const otherTabActivity = ({ flowId = "1", key = "cbv-session-activity", raw } = {}) =>
      window.dispatchEvent(
        new window.StorageEvent("storage", {
          key,
          newValue: raw ?? JSON.stringify({ flowId, at: Date.now() }),
        })
      )

    it("announces this tab's activity, with its flow, when the page loads", () => {
      const announced = JSON.parse(window.localStorage.getItem("cbv-session-activity"))
      expect(announced.flowId).toBe("1")
    })

    it("sends this tab to the 'no longer active' page when another tab is on a different flow", () => {
      otherTabActivity({ flowId: "2" })

      expect(goToSwitchedPage).toHaveBeenCalledTimes(1)
      // and its own timers stop, so it doesn't later warn or end the session
      try {
        vi.advanceTimersByTime(600 * 1000)
      } catch (_) {}
      expect(navigateTo).not.toHaveBeenCalled()
    })

    it("doesn't announce from a page without a flow", async () => {
      application.stop()
      window.localStorage.removeItem("cbv-session-activity")
      setFlowMeta(null)
      application = Application.start()
      application.register("session", SessionController)
      await Promise.resolve()

      expect(window.localStorage.getItem("cbv-session-activity")).toBeNull()
    })

    // Extend is only announced once the server accepts it: a stale tab's
    // Extend is refused and must not push the current tab out.
    describe("Extend", () => {
      const extendFinished = (success) =>
        document.dispatchEvent(
          new window.CustomEvent("turbo:submit-end", {
            detail: {
              success,
              formSubmission: { submitter: document.getElementById("extend-session-button") },
            },
          })
        )

      beforeEach(() => window.localStorage.removeItem("cbv-session-activity"))

      it("isn't announced on click", () => {
        document.getElementById("extend-session-button").click()
        expect(window.localStorage.getItem("cbv-session-activity")).toBeNull()
      })

      it("is announced once the server accepts it", () => {
        extendFinished(true)
        expect(JSON.parse(window.localStorage.getItem("cbv-session-activity")).flowId).toBe("1")
      })

      it("isn't announced when the server refuses it", () => {
        extendFinished(false)
        expect(window.localStorage.getItem("cbv-session-activity")).toBeNull()
      })
    })

    it("doesn't announce from a Turbo preview of an earlier page", async () => {
      application.stop()
      window.localStorage.removeItem("cbv-session-activity")
      document.documentElement.setAttribute("data-turbo-preview", "")
      try {
        setupDOM(600)
        application = Application.start()
        application.register("session", SessionController)
        await Promise.resolve()

        expect(window.localStorage.getItem("cbv-session-activity")).toBeNull()
      } finally {
        document.documentElement.removeAttribute("data-turbo-preview")
      }
    })

    // A page restored from the back-forward cache resumes its old timers;
    // they start over so the timeout isn't sent before the server sees the
    // session as idle.
    it("starts the countdown over when the page is restored from the back-forward cache", () => {
      vi.advanceTimersByTime(590 * 1000)
      const restored = new window.Event("pageshow")
      restored.persisted = true
      window.dispatchEvent(restored)
      vi.advanceTimersByTime(20 * 1000)

      expect(navigateTo).not.toHaveBeenCalled()
    })

    it("leaves the countdown alone on an ordinary page show", () => {
      vi.advanceTimersByTime(590 * 1000)
      window.dispatchEvent(new window.Event("pageshow"))
      vi.advanceTimersByTime(20 * 1000)

      expect(navigateTo).toHaveBeenCalledWith(TIMEOUT_PATH)
    })

    // Back/Forward can put back a page for a flow this browser has moved on
    // from; announcing it would push the current tab out.
    it("doesn't announce from a page put back by Back/Forward", async () => {
      application.stop()
      window.localStorage.removeItem("cbv-session-activity")
      renderedFromHistory.mockReturnValue(true)
      setupDOM(600)
      application = Application.start()
      application.register("session", SessionController)
      await Promise.resolve()

      expect(window.localStorage.getItem("cbv-session-activity")).toBeNull()
    })

    it("treats activity in an older format (no flow) as the same flow", () => {
      vi.advanceTimersByTime(590 * 1000)
      otherTabActivity({ raw: String(Date.now()) })
      vi.advanceTimersByTime(20 * 1000)

      expect(goToSwitchedPage).not.toHaveBeenCalled()
      expect(navigateTo).not.toHaveBeenCalled()
    })

    it("restarts the countdown when another tab is active on the same flow", () => {
      vi.advanceTimersByTime(590 * 1000)
      otherTabActivity()
      vi.advanceTimersByTime(20 * 1000)

      expect(navigateTo).not.toHaveBeenCalled()

      try {
        vi.advanceTimersByTime(600 * 1000)
      } catch (_) {}
      expect(navigateTo).toHaveBeenCalledWith(TIMEOUT_PATH)
    })

    it("ignores other storage changes", () => {
      vi.advanceTimersByTime(590 * 1000)
      otherTabActivity({ key: "something-else" })
      try {
        vi.advanceTimersByTime(20 * 1000)
      } catch (_) {}

      expect(navigateTo).toHaveBeenCalledWith(TIMEOUT_PATH)
    })
  })

  it("tracks ApplicantEndedSession on end button click", async () => {
    const endButton = document.getElementById("end-session-button")
    endButton.click()
    expect(trackUserAction).toHaveBeenCalledWith("ApplicantEndedSession")
  })
})
