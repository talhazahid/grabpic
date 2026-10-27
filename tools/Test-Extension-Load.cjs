const fs = require('fs'), path = require('path'), assert = require('assert');
let pw; try {pw = require('playwright')} catch {pw=require(path.join(process.env.USERPROFILE,'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'))}
(async()=>{
  const root=path.resolve(__dirname,'..'),extension=path.join(root,'dist/Browser/chromium');
  const context=await pw.chromium.launchPersistentContext(path.join(root,'artifacts/extension-qa-'+process.pid),{
    executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true,
    ignoreDefaultArgs:['--disable-extensions'],args:['--disable-extensions-except='+extension,'--load-extension='+extension]
  });
  try {
    const worker=context.serviceWorkers()[0] || await context.waitForEvent('serviceworker',{timeout:15000});
    const identity=await worker.evaluate(()=>({id:chrome.runtime.id,manifest:chrome.runtime.getManifest()}));
    assert.equal(identity.id,'fnnldbdenmkagpnfneogfcfnjpgjjdpl');
    assert.equal(identity.manifest.version,'0.6.0');
    await new Promise(resolve=>setTimeout(resolve,700));
    const exists=await worker.evaluate(()=>new Promise(resolve=>chrome.contextMenus.update('page',{title:'Grab full page (scrolling)'},()=>resolve(!chrome.runtime.lastError))));
    assert.equal(exists,true);
    console.log('PASS actual Edge extension loading, stable native-host identity, MV3 service worker, and installed scrolling-page context menu');
  } finally {await context.close()}
})().catch(error=>{console.error(error);process.exit(1)});
