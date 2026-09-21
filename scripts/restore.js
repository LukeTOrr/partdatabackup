// Re-create every schedule from a snapshot, in the state it was in before teardown.
// Safe to re-run: jobs that already exist are skipped.
const { jobId, createJob, pauseJob, jobExists } = require('../lib/scheduler');
const { loadSnapshot } = require('../lib/store');

async function restore({ bucket, snapshotObject, dryRun }) {
  const snapshot = await loadSnapshot(bucket, snapshotObject || undefined);
  console.log(`[restore] Snapshot from ${snapshot.createdAt}: ${snapshot.jobs.length} schedule(s)`);

  let restored = 0;
  let skipped = 0;
  const failures = [];

  for (const { originalState, job } of snapshot.jobs) {
    const id = jobId(job);
    try {
      if (await jobExists(job.name)) {
        console.log(`[restore] ${id} already exists — skipped`);
        skipped++;
        continue;
      }
      if (dryRun) {
        console.log(`[restore] Would create ${job.name} ("${job.schedule}", ${originalState})`);
        continue;
      }
      await createJob(job);
      if (originalState === 'PAUSED') await pauseJob(job.name);
      console.log(`[restore] Created ${id}${originalState === 'PAUSED' ? ' (paused, as before)' : ''}`);
      restored++;
    } catch (err) {
      console.log(`[restore] Failed ${id}: ${err.message}`);
      failures.push(id);
    }
  }

  if (failures.length) {
    throw new Error(`Restored ${restored}, skipped ${skipped}. Failed: ${failures.join(', ')}`);
  }
  return { count: restored, note: dryRun ? 'dry run' : `restored ${restored}, skipped ${skipped}` };
}

module.exports = { restore };
