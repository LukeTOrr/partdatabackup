// Snapshot → verify → pause → delete every Cloud Scheduler job in the project,
// except this tool's own trigger (which is paused at the end so it can't re-fire).
const { jobId, listAllJobs, toRestorable, pauseJob, deleteJob } = require('../lib/scheduler');
const { saveSnapshot } = require('../lib/store');

async function teardown({ projectId, bucket, selfTrigger, dryRun }) {
  const { jobs, failedLocations } = await listAllJobs(projectId);
  const self = jobs.find((j) => jobId(j) === selfTrigger);
  const targets = jobs.filter((j) => jobId(j) !== selfTrigger);

  console.log(`[teardown] Found ${targets.length} schedule(s) in ${projectId}:`);
  targets.forEach((j) => console.log(`  - ${j.name}  [${j.state}]  "${j.schedule}" ${j.timeZone || ''}`));

  if (!targets.length) {
    // Leave latest.json alone — overwriting it with an empty list would lose the real snapshot.
    console.log('[teardown] Nothing to remove. Existing snapshot left untouched.');
    if (!dryRun && self && self.state === 'ENABLED') await pauseJob(self.name);
    return { count: 0, note: 'nothing to remove' };
  }

  if (dryRun) {
    console.log('[teardown] DRY_RUN=true — no snapshot written, nothing paused or deleted.');
    return { count: 0, note: `dry run: ${targets.length} would be removed` };
  }

  // 1. Snapshot (with each job's original state) — must succeed before anything is touched.
  const snapshot = {
    project: projectId,
    createdAt: new Date().toISOString(),
    jobs: targets.map((j) => ({ originalState: j.state, job: toRestorable(j) })),
  };
  const saved = await saveSnapshot(bucket, snapshot);
  console.log(`[teardown] Snapshot saved + verified: ${saved.dated}`);

  // 2. Pause everything first, so a failed delete still leaves the job inert.
  for (const j of targets) {
    if (j.state !== 'ENABLED') continue;
    try {
      await pauseJob(j.name);
      console.log(`[teardown] Paused ${jobId(j)}`);
    } catch (err) {
      console.log(`[teardown] Pause failed for ${jobId(j)} (continuing to delete): ${err.message}`);
    }
  }

  // 3. Delete.
  const failures = [];
  for (const j of targets) {
    try {
      await deleteJob(j.name);
      console.log(`[teardown] Deleted ${jobId(j)}`);
    } catch (err) {
      console.log(`[teardown] Delete failed for ${jobId(j)}: ${err.message}`);
      failures.push(jobId(j));
    }
  }

  // 4. Disarm our own trigger so it doesn't fire again next year.
  if (self && self.state === 'ENABLED') {
    await pauseJob(self.name);
    console.log(`[teardown] Paused own trigger ${selfTrigger}`);
  }

  const deleted = targets.length - failures.length;
  if (failures.length) {
    throw new Error(`Deleted ${deleted}/${targets.length}. Failed: ${failures.join(', ')}. Snapshot: ${saved.dated}`);
  }
  const warn = failedLocations.length ? ` (could not list: ${failedLocations.join(', ')})` : '';
  return { count: deleted, note: `deleted ${deleted}, snapshot ${saved.dated}${warn}` };
}

module.exports = { teardown };
