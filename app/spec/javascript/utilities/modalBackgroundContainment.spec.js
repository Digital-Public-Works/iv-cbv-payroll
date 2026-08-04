import { describe, it, expect, afterEach } from "vitest"
import {
  onceElementAppears,
  containBackgroundFocus,
} from "@js/utilities/modalBackgroundContainment"

function flushMicrotasks() {
  return Promise.resolve()
}

describe("onceElementAppears", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("calls back immediately if a matching element already exists", () => {
    const existing = document.createElement("div")
    existing.id = "argyle-link-root-existing"
    document.body.appendChild(existing)

    let found
    onceElementAppears('div[id*="argyle-link-root"]', (el) => {
      found = el
    })

    expect(found).toBe(existing)
  })

  it("calls back once a matching element is added to document.body", async () => {
    let found
    onceElementAppears('div[id*="argyle-link-root"]', (el) => {
      found = el
    })

    const added = document.createElement("div")
    added.id = "argyle-link-root-abc"
    document.body.appendChild(added)
    await flushMicrotasks()

    expect(found).toBe(added)
  })

  it("ignores added elements that don't match the selector", async () => {
    let found
    onceElementAppears('div[id*="argyle-link-root"]', (el) => {
      found = el
    })

    document.body.appendChild(document.createElement("button"))
    await flushMicrotasks()

    expect(found).toBeUndefined()
  })

  it("stops watching once cancelled", async () => {
    let found
    const cancel = onceElementAppears('div[id*="argyle-link-root"]', (el) => {
      found = el
    })
    cancel()

    const added = document.createElement("div")
    added.id = "argyle-link-root-abc"
    document.body.appendChild(added)
    await flushMicrotasks()

    expect(found).toBeUndefined()
  })
})

describe("containBackgroundFocus", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("inerts every other direct child of document.body", () => {
    const visible = document.createElement("div")
    const sibling1 = document.createElement("div")
    const sibling2 = document.createElement("div")
    document.body.append(sibling1, visible, sibling2)

    containBackgroundFocus(visible)

    expect(visible.inert).toBeFalsy()
    expect(sibling1.inert).toBe(true)
    expect(sibling2.inert).toBe(true)
  })

  it("releases exactly the elements it inerted", () => {
    const visible = document.createElement("div")
    const sibling = document.createElement("div")
    document.body.append(sibling, visible)

    const release = containBackgroundFocus(visible)
    expect(sibling.inert).toBe(true)

    release()

    expect(sibling.inert).toBe(false)
    expect(visible.inert).toBeFalsy()
  })
})
