require('dotenv').config();
const { logStart, logEnd } = require('./lib/log');

// ── Poka-yoke: refuse to run with missing config ────────────────────────────
const REQUIRED_ENV = ['JOB_NAME', 'PROJECT_ID', 'SNAPSHOT_BUCKET', 'SELF_TRIGGER_NAME'];

const missing = REQUIRED_ENV.filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`[launch] Missing required .env keys: ${missing.join(', ')}`);
  console.error('[launch] Copy .env.example to .env and fill them in.');
  process.exit(1);
}

// ── Mode: `node launch.js teardown` (default) | `node launch.js restore [object]` ──
const MODES = ['teardown', 'restore'];
const mode = (process.argv[2] || process.env.MODE || 'teardown').toLowerCase();
if (!MODES.includes(mode)) {
  console.error(`[launch] Unknown mode "${mode}". Use one of: ${MODES.join(', ')}`);
  process.exit(1);
}

const { teardown } = require('./scripts/teardown');
const { restore } = require('./scripts/restore');

const config = {
  projectId: process.env.PROJECT_ID,
  bucket: process.env.SNAPSHOT_BUCKET,
  selfTrigger: process.env.SELF_TRIGGER_NAME,
  snapshotObject: process.argv[3] || process.env.SNAPSHOT_OBJECT, // e.g. snapshots/2026-09-25T19-00-00-000Z.json
  dryRun: process.env.DRY_RUN === 'true',
};

async function main() {
  const run = await logStart(`${process.env.JOB_NAME} (${mode})`);
  console.log(`[launch] Mode: ${mode}${config.dryRun ? ' (DRY RUN)' : ''} — project ${config.projectId}`);
  try {
    const result = mode === 'restore' ? await restore(config) : await teardown(config);
    await logEnd(run, 'SUCCESS', result.note, result.count);
    console.log('[launch] All steps complete.');
  } catch (err) {
    console.error('[launch] FATAL:', err);
    await logEnd(run, 'FAIL', String(err && err.message ? err.message : err), 0);
    process.exit(1);
  }
}

main();
