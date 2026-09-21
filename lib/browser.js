// Puppeteer helpers — replaces the two habits that make scrapers flaky:
// fixed waitForTimeout() sleeps, and unguarded clicks on brittle selectors.
const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

// headless: false locally by default (you watch runs); HEADLESS=true for Cloud Run.
async function launchBrowser(downloadDir) {
  const browser = await puppeteer.launch({
    headless: process.env.HEADLESS === 'true' ? 'new' : false,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  if (downloadDir) {
    fs.mkdirSync(downloadDir, { recursive: true });
    const client = await page.target().createCDPSession();
    await client.send('Page.setDownloadBehavior', {
      behavior: 'allow',
      downloadPath: path.resolve(downloadDir),
    });
  }
  return { browser, page };
}

// Wait for the element, THEN act. Never a bare sleep before a click/type.
async function clickWhenReady(page, selector, timeout = 15000) {
  await page.waitForSelector(selector, { visible: true, timeout });
  await page.click(selector);
}

async function typeInto(page, selector, text, timeout = 15000) {
  await page.waitForSelector(selector, { visible: true, timeout });
  await page.click(selector, { clickCount: 3 }); // select existing content
  await page.type(selector, text);
}

// Retry a flaky step once (portal hiccup, slow table load), then fail LOUDLY.
// Usage: await withRetry('download RG report', () => downloadReport(page));
async function withRetry(label, fn, retries = 1, waitMs = 5000) {
  for (let attempt = 0; ; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt >= retries) {
        console.error(`[retry] "${label}" failed after ${attempt + 1} attempt(s).`);
        throw err;
      }
      console.log(`[retry] "${label}" failed (${err.message}) — retrying in ${waitMs / 1000}s...`);
      await new Promise((r) => setTimeout(r, waitMs));
    }
  }
}

// Wait for a NEW file to finish downloading into dir (no .crdownload left).
async function waitForDownload(dir, timeoutMs = 60000) {
  const before = new Set(fs.readdirSync(dir));
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const now = fs.readdirSync(dir);
    const fresh = now.filter((f) => !before.has(f) && !f.endsWith('.crdownload'));
    if (fresh.length) return path.join(dir, fresh[0]);
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`Download did not complete within ${timeoutMs / 1000}s in ${dir}`);
}

module.exports = { launchBrowser, clickWhenReady, typeInto, withRetry, waitForDownload };
