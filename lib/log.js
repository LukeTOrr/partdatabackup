// JobLog heartbeat — every scheduled job's last act is one row to a shared sheet:
//   [ job, started, finished, status, message, rows ]
// One sheet for ALL jobs = your fleet control chart. Set HEARTBEAT_SHEET_ID in .env
// (same ID in every project). If unset, logging is skipped so ad-hoc runs still work.
const { appendRows } = require('./sheets');

const SHEET_ID = process.env.HEARTBEAT_SHEET_ID;
const TAB = process.env.HEARTBEAT_TAB || 'JobLog';

async function logStart(jobName) {
  return { jobName: jobName || 'unnamed-job', started: new Date() };
}

async function logEnd(run, status, message = '', rows = 0) {
  const finished = new Date();
  const line = [
    run.jobName,
    run.started.toLocaleString('en-US'),
    finished.toLocaleString('en-US'),
    status, // SUCCESS | FAIL
    message,
    rows,
  ];
  console.log(`[joblog] ${run.jobName}: ${status}${message ? ' — ' + message : ''}`);
  if (!SHEET_ID) return; // heartbeat optional for one-off scripts
  try {
    await appendRows(SHEET_ID, TAB, [line]);
  } catch (err) {
    // Never let the heartbeat kill the job it reports on.
    console.error('[joblog] Failed to write heartbeat:', err.message);
  }
}

module.exports = { logStart, logEnd };
