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
