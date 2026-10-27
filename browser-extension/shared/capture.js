const api = globalThis.browser || chrome;
const params = new URLSearchParams(location.search);
const tabId = Number(params.get('tab')), windowId = Number(params.get('window')), mode = params.get('mode');
const status = document.querySelector('#status'), button = document.querySelector('#cancel');
let cancelled = false;
button.onclick = () => { cancelled = true; button.disabled = true; };
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// This function is serialized by scripting.executeScript. No extension closures are used.
async function pageStep(action, x, y) {
  const key = '__grabpicCaptureState';
  if (action === 'restore') {
    const saved = window[key]; if (!saved) return;
    for (const [element, value, priority] of saved.hidden) element.style.setProperty('visibility', value, priority);
    clearInterval(saved.watchdog); window.scrollTo(saved.x, saved.y); saved.style.remove(); delete window[key]; return;
  }
  if (action === 'start') {
    if (window[key]) throw new Error('This page already has a capture in progress.');
    const style = document.createElement('style');
    style.textContent = 'html,body,*{scroll-behavior:auto!important;scroll-snap-type:none!important;overflow-anchor:none!important}html,body{scrollbar-width:none!important}html::-webkit-scrollbar,body::-webkit-scrollbar{display:none!important}*{animation-play-state:paused!important;caret-color:transparent!important}';
    document.documentElement.append(style);
    const state = window[key] = { x: scrollX, y: scrollY, style, hidden: [], touched: Date.now(), fixed: [...document.querySelectorAll('*')].filter(e => ['fixed', 'sticky'].includes(getComputedStyle(e).position)) };
    state.watchdog = setInterval(() => {
      if (Date.now() - state.touched < 30000) return;
      for (const [element, value, priority] of state.hidden) element.style.setProperty('visibility', value, priority);
      window.scrollTo(state.x, state.y); style.remove(); clearInterval(state.watchdog); delete window[key];
    }, 1000);
  }
  if (action === 'scroll') {
    const saved = window[key]; if (!saved) throw new Error('The page changed during capture.');
    saved.touched = Date.now();
    if (y > 0 || x > 0) for (const element of saved.fixed) {
      if (!saved.hidden.some(entry => entry[0] === element)) saved.hidden.push([element, element.style.getPropertyValue('visibility'), element.style.getPropertyPriority('visibility')]);
      element.style.setProperty('visibility', 'hidden', 'important');
    }
    window.scrollTo(x, y);
    await new Promise(resolve => setTimeout(resolve, 180));
  }
  return { x: scrollX, y: scrollY, width: innerWidth, height: innerHeight, viewportHeight: innerHeight,
    totalWidth: Math.max(document.documentElement.scrollWidth, document.body?.scrollWidth || 0),
    totalHeight: Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight || 0), dpr: devicePixelRatio, url: location.href };
}
async function step(action, x = 0, y = 0) {
  const result = await api.scripting.executeScript({ target: { tabId }, func: pageStep, args: [action, x, y] });
  return result[0].result;
}
async function checkTarget() {
  if (cancelled) throw new Error('Capture cancelled.');
  const tab = await api.tabs.get(tabId);
  if (!tab.active || tab.windowId !== windowId) throw new Error('The active tab changed. Please retry without switching tabs.');
}
async function image() {
  await checkTarget();
  const data = await api.tabs.captureVisibleTab(windowId, { format: 'png' });
  await checkTarget();
  const img = new Image(); img.src = data; await img.decode(); return img;
}
async function run() {
  let started = false, result;
  try {
    // Check the local companion before moving the page or taking a screenshot.
    const probe = await api.runtime.sendNativeMessage('com.owl.grabpic', { action: 'ping' });
    if (!probe.ok) throw new Error(probe.error);
    if (mode === 'area') {
      const sent = await api.runtime.sendNativeMessage('com.owl.grabpic', { action: 'area' });
      if (!sent.ok) throw new Error(sent.error); window.close(); return;
    }
    if (mode === 'view') { const img = await image(); result = img.src; }
    else {
      let first = await step('start'); started = true;
      const url = first.url, initialDpr = first.dpr;
      // Bound infinite/lazy pages and canvas memory; never quietly truncate the page.
      const canvas = document.createElement('canvas'); let context, scale, width, height;
      let y = 0, rows = 0;
      do {
        let x = 0;
        do {
          await checkTarget();
          const state = await step('scroll', x, y);
          if (state.url !== url || state.dpr !== initialDpr || state.width !== first.width || state.height !== first.height) throw new Error('Page layout, zoom, or navigation changed. Please retry.');
          const img = await image();
          if (!context) {
            scale = img.height / state.viewportHeight; width = Math.ceil(state.totalWidth * scale); height = Math.ceil(state.totalHeight * scale);
            if (width > 32700 || height > 32700 || width * height > 60_000_000) throw new Error('This page is too large for one image. Try selecting an area.');
            canvas.width = width; canvas.height = height; context = canvas.getContext('2d');
          }
          const nextHeight = Math.ceil(state.totalHeight * scale);
          if (nextHeight !== height || Math.ceil(state.totalWidth * scale) !== width) throw new Error('Page size changed while loading. Let the page finish loading and retry.');
          // The final scroll clamps at the document edge. Crop overlap instead of overwriting earlier tiles.
          const sourceX = Math.round((x - state.x) * scale), sourceY = Math.round((y - state.y) * scale);
          const destinationX = Math.round(x * scale), destinationY = Math.round(y * scale);
          const tileWidth = Math.min(Math.round(state.width * scale) - sourceX, width - destinationX);
          const tileHeight = Math.min(Math.round(state.height * scale) - sourceY, height - destinationY);
          if (sourceX < 0 || sourceY < 0 || tileWidth <= 0 || tileHeight <= 0) throw new Error('The page moved unexpectedly. Please retry.');
          context.drawImage(img, sourceX, sourceY, tileWidth, tileHeight, destinationX, destinationY, tileWidth, tileHeight);
          status.textContent = `Capturing page… ${Math.min(100, Math.round((state.y + state.height) * scale / height * 100))}%`;
          if (state.x + state.width >= width / scale - 1) break;
          const nextX = state.x + state.width; if (nextX <= x && x > 0) throw new Error('This page does not support standard scrolling.'); x = nextX;
          await sleep(550);
        } while (true);
        const state = await step('measure');
        if (state.y + state.height >= height / scale - 1) break;
        const nextY = state.y + state.height; if (nextY <= y && rows > 0) throw new Error('This page does not support standard scrolling.'); y = nextY;
        if (++rows > 200) throw new Error('Page capture limit reached.');
        await sleep(550);
      } while (true);
      result = canvas.toDataURL('image/png');
      if (result === 'data:,') throw new Error('The browser could not create an image this large.');
    }
  } finally { if (started) { try { await step('restore'); } catch {} } }
  if (cancelled) throw new Error('Capture cancelled.');
  status.textContent = 'Sending to Grabpic…';
  const response = await api.runtime.sendNativeMessage('com.owl.grabpic', { action: 'image', data: result });
  if (!response.ok) throw new Error(response.error);
  status.textContent = response.message;
  button.disabled = false; button.textContent = 'Close'; button.onclick = () => window.close();
}
run().catch(error => {
  status.textContent = `${error.message} If the companion is unavailable, install/open Grabpic 0.6.0 first. Browser-internal pages and extension stores cannot be scrolled by extensions.`;
  button.disabled = false; button.textContent = 'Close'; button.onclick = () => window.close();
});
