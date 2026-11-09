export function toggleErrorIds(target, error, id) {
  const describedbyList = target.getAttribute("aria-describedby")
  if (error && describedbyList.includes(id)) return
  let describeIds

  if (error) {
    describeIds = id + " " + describedbyList
  } else {
    describeIds = describedbyList.replace(id, "").trim()
  }

  target.setAttribute("aria-describedby", describeIds)
}

// TODO: Add a guard around race conditions in case multiple components are calling this function
// --> potential for first one not to be read out by SR if it gets replaced too quickly
export function updateAriaLiveRegion(text) {
  const liveRegion = document.getElementById("live-announcer")
  liveRegion.replaceChildren()
  if (text) {
    liveRegion.textContent = text
  }
}

// Native <a> elements only activate on Enter, not Space, unlike real
// <button> elements. Use this to give an anchor styled/announced as a
// button (role="button") the same Space-key activation a real button gets
// for free. Bind via a Stimulus action, e.g. data-action="keydown->my-controller#activateWithSpace".
export function activateWithSpace(event) {
  if (event.key !== " " && event.key !== "Spacebar") return
  event.preventDefault()
  event.currentTarget.click()
}
