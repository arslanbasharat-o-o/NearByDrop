import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const source = html.match(/<script>\s*\/\/ Copy Command[\s\S]*?<\/script>/)[0]
  .replace(/^<script>|<\/script>$/g, '')
  .split('// Initialize default issue content on load')[0];
const nodes = new Map();
function node(id) {
  if (!nodes.has(id)) {
    const classes = new Set(id === 'faqContent2' ? ['hidden'] : []);
    nodes.set(id, {
      innerText: '', attrs: {}, value: 'wifi',
      classList: { contains: c => classes.has(c), add: c => classes.add(c), remove: c => classes.delete(c) },
      setAttribute(k, v) { this.attrs[k] = v; },
      closest() { return null; },
    });
  }
  return nodes.get(id);
}
const context = vm.createContext({
  document: { getElementById: node, querySelector: selector => node(selector), querySelectorAll: () => [] },
  window: { addEventListener() {} }, location: { hash: '' },
  navigator: { clipboard: { writeText: () => Promise.reject(new Error('Clipboard denied')) } },
  setTimeout() {},
});
vm.runInContext(source, context);
for (const n of [1, 2]) {
  for (let i = 0; i < 2; i++) {
    context.toggleFaq(n);
    assert.equal(node(`[aria-controls="faqContent${n}"]`).attrs['aria-expanded'], String(!node(`faqContent${n}`).classList.contains('hidden')));
  }
}
node('transferMode').value = 'usb'; context.runCompatibilityCheck();
assert.match(node('compatTitle').innerText, /USB MTP/);
node('transferMode').value = 'wifi'; context.runCompatibilityCheck();
assert.match(node('compatTitle').innerText, /Quick Share/);
for (const [i, key] of ['not-found', 'blocked-wifi', 'gatekeeper', 'large-files'].entries()) {
  context.showIssue(key);
  assert.equal(node(`tabIssue${i + 1}`).attrs['aria-pressed'], 'true');
  assert.match(node('issueContent').innerHTML, /ISSUE:/);
}
const outer = { open: false };
const details = { open: false, parentElement: { closest: () => outer } };
node('troubleshooting').closest = () => details;
context.revealAnchor('#troubleshooting');
assert.equal(details.open, true);
assert.equal(outer.open, true);
context.copyCmd(); await new Promise(resolve => setImmediate(resolve));
assert.equal(node('copyLabel').innerText, 'SELECT & COPY COMMAND');
console.log('Site interactions passed: FAQs, transfer modes, diagnostics, deep links, clipboard failure.');

// Shared direct toggle: all site pages keep the same preference and palette.
assert.ok(html.indexOf('src="assets/site-theme.js?v=3"') < html.indexOf('<body'));
assert.match(html, /data-theme-toggle aria-label="Switch color theme"/);
assert.doesNotMatch(html, /data-theme-menu|data-theme-select|appearance-panel/);
assert.doesNotMatch(html, /VERSION 2\.3\.4 AVAILABLE/);
const themeSource = readFileSync(new URL('../docs/assets/site-theme.js', import.meta.url), 'utf8');
for (const initial of ['light', 'dark', 'system', null, 'invalid']) {
  for (const blockedStorage of [false, true]) {
    let saved = initial;
    const root = { dataset: {} };
    const meta = {};
    const listeners = {};
    let themeEvents = 0;
    const button = { attrs: {}, setAttribute(k, v) { this.attrs[k] = v; }, addEventListener: (_, fn) => { listeners.click = fn; } };
    const media = { matches: false, addEventListener: (_, fn) => { listeners.media = fn; } };
    const ctx = vm.createContext({
      document: {
        documentElement: root, querySelector: () => meta,
        querySelectorAll: () => [button], addEventListener: (_, fn) => { listeners.ready = fn; },
      },
      window: { dispatchEvent: () => { themeEvents++; }, addEventListener: (_, fn) => { listeners.storage = fn; } },
      Event: class { constructor(type) { this.type = type; } },
      localStorage: {
        getItem: () => { if (blockedStorage) throw Error('Storage blocked'); return saved; },
        setItem: (_, value) => { if (blockedStorage) throw Error('Storage blocked'); saved = value; },
      },
      matchMedia: () => media,
    });
    vm.runInContext(themeSource, ctx);
    const explicit = !blockedStorage && ['light', 'dark'].includes(initial);
    assert.equal(root.dataset.theme, explicit ? initial : 'light');
    listeners.ready();
    media.matches = true; listeners.media();
    assert.equal(root.dataset.theme, explicit ? initial : 'dark');
    const before = root.dataset.theme;
    listeners.click();
    assert.equal(root.dataset.theme, before === 'dark' ? 'light' : 'dark');
    assert.equal(button.attrs['aria-label'], 'Switch to ' + before + ' mode');
    assert.equal(meta.content, root.dataset.theme === 'light' ? '#ffffff' : '#070707');
    const chosen = root.dataset.theme;
    media.matches = false; listeners.media();
    assert.equal(root.dataset.theme, chosen, 'Explicit choice must survive OS change');
    listeners.click(); assert.equal(root.dataset.theme, before);
    if (!blockedStorage) assert.equal(saved, before);
    listeners.storage({ key: 'nearby-drop-theme', newValue: 'light' });
    assert.equal(root.dataset.theme, 'light');
    assert.ok(themeEvents >= 4, 'Canvas must be notified when the palette changes');
  }
}
for (const match of html.matchAll(/<script(?![^>]*type="application\/ld\+json")[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(match[1]);
console.log('Shared direct theme toggle passed: persistence, OS defaults, blocked storage, cross-tab sync, canvas notifications.');
