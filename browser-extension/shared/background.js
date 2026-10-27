/* Browser UI integration stays in the extension; the Windows shell menu cannot modify it. */
const api = globalThis.browser || chrome;
api.runtime.onInstalled.addListener(async () => {
  await api.contextMenus.removeAll();
    api.contextMenus.create({ id: 'grabpic', title: 'Grabpic', contexts: ['all'], documentUrlPatterns: ['http://*/*', 'https://*/*'] });
    for (const [id, title] of [['page', 'Grab full page (scrolling)'], ['view', 'Grab visible view'], ['area', 'Grab area']]) {
      api.contextMenus.create({ id, parentId: 'grabpic', title, contexts: ['all'], documentUrlPatterns: ['http://*/*', 'https://*/*'] });
    }
});
api.contextMenus.onClicked.addListener((info, tab) => {
  if (!['page', 'view', 'area'].includes(info.menuItemId) || !tab?.id) return;
  const query = new URLSearchParams({ tab: tab.id, window: tab.windowId, mode: info.menuItemId });
  api.windows.create({ url: api.runtime.getURL('capture.html') + '?' + query, type: 'popup', focused: false, width: 440, height: 290 });
});
