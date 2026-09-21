require('dotenv').config();
const { logStart, logEnd } = require('./lib/log');

// ── Poka-yoke: refuse to run with missing config ────────────────────────────
// List every env key this job needs. Add/remove as the project requires.
const REQUIRED_ENV = [
  'JOB_NAME',
  // 'PORTAL_USER',
  // 'PORTAL_PASS',
  // 'SPREADSHEET_ID',
];

const missing = REQUIRED_ENV.filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`[launch] Missing required .env keys: ${missing.join(', ')}`);
  console.error('[launch] Copy .env.example to .env and fill them in.');
  process.exit(1);
}

// ── Steps: one require per pipeline stage, one call per line ────────────────
// const { download }    = require('./scripts/download');
// const { consolidate } = require('./scripts/consolidate');
// const { upload }      = require('./scripts/upload');

async function main() {
  const run = await logStart(process.env.JOB_NAME);
  try {
    // await download();
    // await consolidate();
    // const rows = await upload();
    const rows = 0; // set to the number of rows written, if applicable

    await logEnd(run, 'SUCCESS', '', rows);
    console.log('[launch] All steps complete.');
  } catch (err) {
    console.error('[launch] FATAL:', err);
    await logEnd(run, 'FAIL', String(err && err.message ? err.message : err), 0);
    process.exit(1);
  }
}

main();
