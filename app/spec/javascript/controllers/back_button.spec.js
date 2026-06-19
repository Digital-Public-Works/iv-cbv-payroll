import { vi, describe, beforeEach, it, expect } from "vitest"
import BackButtonController from "@js/controllers/cbv/back_button_controller"
import { trackUserAction } from "@js/utilities/api"

describe("BackButtonController", () => {
  let container
  let backButton
  
  beforeEach(() => {
    container = document.createElement("div")
    container.setAttribute("data-controller", "back-button")
    
    backButton = document.createElement("button")
    backButton.type = "button"
    backButton.textContent = "Back"
    backButton.setAttribute("data-action", "click->back-button#back")
    
    container.appendChild(backButton)
    document.body.appendChild(container)    
    
    vi.spyOn(backButton, "addEventListener")
    vi.spyOn(backButton, "removeEventListener")

    window.Stimulus.register("back-button", BackButtonController)
  })
  
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("calls trackUserAction with data attributes for back", async () => {
    await backButton.click()
    expect(await trackUserAction).toBeCalledTimes(1)
    expect(trackUserAction.mock.calls[0]).toMatchSnapshot()
  })
})