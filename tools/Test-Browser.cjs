const fs = require('fs'), path = require('path'), assert = require('assert');
let playwright;
try { playwright = require('playwright'); } catch { playwright = require(path.join(process.env.USERPROFILE, '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright')); }
const { chromium } = playwright;
const { spawn } = require('child_process');
const root = path.resolve(__dirname, '..');
process.env.GRABPIC_PROFILE_DIRECTORY = path.join(root, 'artifacts/browser-test-profile-' + process.pid);
process.env.GRABPIC_SCREENSHOT_MODE = '1';
async function native(message) {
  const child = spawn(path.join(root, 'dist/GrabPic/GrabPic.BrowserHost.exe'), [], { windowsHide: true });
  const data = Buffer.from(JSON.stringify(message)), header = Buffer.alloc(4); header.writeUInt32LE(data.length);
  const output = [];
  const done = new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill(); reject(new Error('Native bridge response timed out.')); }, 50000);
    child.on('error', error => {clearTimeout(timer);reject(error)});
    child.stdout.on('data', chunk => {
      output.push(chunk); const bytes=Buffer.concat(output);
      if(bytes.length>=4 && bytes.length>=bytes.readUInt32LE()+4) {
        clearTimeout(timer);
        try { resolve(JSON.parse(bytes.subarray(4,bytes.readUInt32LE()+4))); } catch(error) {reject(error)}
      }
    });
    child.on('exit', code => {if(code && !output.length){clearTimeout(timer);reject(new Error('Native bridge exited without a response.'))}});
  });
  child.stdin.end(Buffer.concat([header, data])); return done;
}
(async () => {
  assert.equal((await native({ action: 'ping' })).version, '0.6.0');
  assert.equal((await native({ action: 'bad' })).ok, false);
  assert.equal((await native({ action: 'image', data: 'file:///private' })).ok, false);
  console.log('PASS native framing, ping, unknown action, invalid image rejection');
  const installed = path.join(process.env.LOCALAPPDATA, 'ms-playwright');
  const chromiumFolder = fs.readdirSync(installed).find(name => /^chromium-\d+$/.test(name));
  const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
  const executablePath = process.env.GRABPIC_TEST_BROWSER || (fs.existsSync(edge) ? edge : path.join(installed, chromiumFolder, 'chrome-win64/chrome.exe'));
  const browser = await chromium.launch({ headless: true, executablePath, ignoreDefaultArgs: ['--hide-scrollbars'] });
  const server = require('http').createServer((_, res) => res.end('<p id="status"></p><button id="cancel">Cancel</button>'));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = 'http://127.0.0.1:' + server.address().port;
  const page = await browser.newPage({ viewport: { width: 900, height: 600 }, deviceScaleFactor: 1 });
  const progress = await browser.newPage({ viewport: { width: 440, height: 290 } });
  let received, changeTab = false, cancel = false;
  await progress.exposeFunction('testStep', async (action, x, y, source) => page.evaluate(({ action, x, y, source }) => (0, eval)('(' + source + ')')(action, x, y), { action, x, y, source }));
  await progress.exposeFunction('testImage', async () => 'data:image/png;base64,' + (await page.screenshot()).toString('base64'));
  await progress.exposeFunction('testTab', async () => ({ active: !changeTab, windowId: 1 }));
  await progress.exposeFunction('testNative', async message => { if (message.action === 'image') received = message.data; return { ok: true, message: 'Saved' }; });
  async function setup(mode, html) {
    received = null; changeTab = false;
    await page.setContent(html);
    await page.evaluate(() => scrollTo(0, 250));
    await progress.goto(origin);
    await progress.setContent('<p id="status"></p><button id="cancel">Cancel</button>');
    await progress.evaluate(mode => {
      history.replaceState(null, '', '?tab=1&window=1&mode=' + mode);
      window.chrome = { tabs: { get: () => window.testTab(), captureVisibleTab: () => window.testImage() },
        scripting: { executeScript: async ({func, args}) => [{result: await window.testStep(...args, func.toString())}] },
        runtime: { sendNativeMessage: (_, message) => window.testNative(message) } };
    }, mode);
    await progress.addScriptTag({ content: fs.readFileSync(path.join(root, 'browser-extension/shared/capture.js'), 'utf8') });
  }
  const html = '<style>html,body{margin:0}body{width:900px;height:1750px;background:linear-gradient(#ff0000,#0000ff)}header{position:fixed;top:0;background:#00ff00;width:900px;height:40px}</style><header>Fixed</header>';
  await setup('page', html);
  await progress.waitForFunction(() => document.querySelector('#status').textContent === 'Saved', {timeout: 15000});
  assert(received); const dims = await progress.evaluate(data => new Promise(resolve => { const img = new Image(); img.onload = () => { const c=document.createElement('canvas');c.width=img.width;c.height=img.height;const g=c.getContext('2d');g.drawImage(img,0,0);resolve({w:img.width,h:img.height,top:[...g.getImageData(800,10,1,1).data],middle:[...g.getImageData(800,610,1,1).data],bottom:[...g.getImageData(800,1740,1,1).data]}); }; img.src=data; }), received);
  assert.equal(dims.w,900); assert.equal(dims.h,1750); assert.equal(dims.top[1],255); assert(dims.middle[1]<10); assert.equal(dims.middle[3],255); assert.equal(dims.bottom[3],255); assert(dims.bottom[2]>240);
  assert.equal(await page.evaluate(() => scrollY), 250);
  assert.equal(await page.locator('header').evaluate(e => e.style.visibility), '');
  fs.writeFileSync(path.join(root,'artifacts/browser-full-page.png'), Buffer.from(received.split(',')[1], 'base64'));
  const profile = process.env.GRABPIC_PROFILE_DIRECTORY; fs.mkdirSync(profile, {recursive:true});
  fs.writeFileSync(path.join(profile,'settings.json'),JSON.stringify({Folder:path.join(profile,'captures'),SettingsVersion:1,Copy:true,Quality:100}));
  const saved = await native({action:'image',data:received}); assert.equal(saved.ok,true,saved.error);
  const latest = JSON.parse(fs.readFileSync(path.join(profile,'latest-capture.json'),'utf8'));
  assert(fs.existsSync(latest)); assert.equal(fs.readdirSync(path.join(profile,'BrowserInbox')).length,0);
  spawn(path.join(root,'dist/GrabPic/GrabPic.exe'),['quit'],{windowsHide:true});
  console.log('PASS actual native host → running app → date folder save, receipt, latest capture, and temporary-file cleanup');
  console.log('PASS full-page 900x1750 stitching, fixed-header deduplication, original scroll/style restoration');
  await setup('page', '<!doctype html><style>html,body{margin:0}body{width:1450px;height:1750px;background:#6543ab}</style>');
  await progress.waitForFunction(() => document.querySelector('#status').textContent === 'Saved');
  const wide = await progress.evaluate(data => new Promise(resolve => {const i=new Image();i.onload=()=>{const c=document.createElement('canvas');c.width=i.width;c.height=i.height;const g=c.getContext('2d');g.drawImage(i,0,0);resolve({w:i.width,h:i.height,edge:[...g.getImageData(1440,1740,1,1).data]})};i.src=data}),received);
  assert.equal(wide.w,1450);assert.equal(wide.h,1750);assert.deepEqual(wide.edge,[101,67,171,255]);
  console.log('PASS standards-mode horizontal + vertical stitching and bottom-right pixel integrity');
  await setup('page', '<!doctype html><style>body{height:50000px}</style>');
  await progress.waitForFunction(() => document.querySelector('#status').textContent.includes('too large'));
  assert.equal(received,null);assert.equal(await page.evaluate(()=>!!window.__grabpicCaptureState),false);
  console.log('PASS oversized-page rejection and cleanup');
  await setup('view', html);
  await progress.waitForFunction(() => document.querySelector('#status').textContent === 'Saved');
  assert(received); console.log('PASS visible-view capture');
  await setup('page', html);
  await progress.locator('#cancel').click();
  await progress.waitForFunction(() => document.querySelector('#status').textContent.includes('cancelled'));
  assert.equal(received,null); assert.equal(await page.evaluate(() => !!window.__grabpicCaptureState),false);
  console.log('PASS cancellation restores page without sending image');
  await setup('page', html); changeTab = true;
  await progress.waitForFunction(() => document.querySelector('#status').textContent.includes('active tab changed'));
  assert.equal(received,null); console.log('PASS tab-switch rejection');
  await browser.close();
  server.close();
})().catch(error => {console.error(error);process.exit(1)});
