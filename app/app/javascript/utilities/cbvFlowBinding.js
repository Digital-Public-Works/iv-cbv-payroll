// each tab needs to know which flow it is part of to determine if it is stale.
export const CBV_FLOW_HEADER = "X-CBV-Flow-Id"
export const CBV_FLOW_PARAM = "cbv_flow_tab_id"
const SWITCHED_PATH = "/cbv/session/switched"

// new flow from invitation link or generic means all previous tabs are stale
const STARTS_NEW_FLOW = /^\/(?:[a-z]{2}\/)?start(?:\/|$)/

export const currentCbvFlowId = () =>
  document.querySelector('meta[name="cbv-flow-id"]')?.content || null

export const cbvFlowHeaders = (url = window.location.href) => {
  const flowId = currentCbvFlowId()
  if (!flowId) return {}

  let target
  try {
    target = new URL(url, window.location.href)
  } catch {
    return {}
  }
  if (target.origin !== window.location.origin) return {}
  if (STARTS_NEW_FLOW.test(target.pathname) || target.searchParams.has("token")) return {}

  return { [CBV_FLOW_HEADER]: flowId }
}

export const localizedPath = (path) => {
  const locale = document.documentElement.lang
  return locale ? `/${locale}${path}` : path
}

export const switchedPagePath = () => localizedPath(SWITCHED_PATH)

export const navigateTo = (path) => window.location.assign(path)

export const goToSwitchedPage = () => navigateTo(switchedPagePath())

export const addCbvFlowField = (form) => {
  const flowId = currentCbvFlowId()
  if (!flowId) return

  let field = form.querySelector(`input[name="${CBV_FLOW_PARAM}"]`)
  if (!field) {
    field = document.createElement("input")
    field.type = "hidden"
    field.name = CBV_FLOW_PARAM
    form.appendChild(field)
  }
  field.value = flowId
}

let lastVisitAction = null

export const renderedFromHistory = () => lastVisitAction === "restore"

export const installCbvFlowBinding = () => {
  document.addEventListener("turbo:visit", (event) => {
    lastVisitAction = event.detail?.action ?? null
  })

  document.addEventListener("turbo:before-fetch-request", (event) => {
    const { fetchOptions, url } = event.detail
    fetchOptions.headers = { ...fetchOptions.headers, ...cbvFlowHeaders(url) }
  })

  // if an in-page frame action is now stale, redirect user to the 'stale' page
  document.addEventListener("turbo:frame-missing", (event) => {
    const { response, visit } = event.detail
    if (new URL(response.url).pathname.endsWith(SWITCHED_PATH)) {
      event.preventDefault()
      visit(response)
    }
  })
}
