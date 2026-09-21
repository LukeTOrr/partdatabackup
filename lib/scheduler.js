// Cloud Scheduler helpers — list every job in every region, pause/delete/create.
const { google } = require('googleapis');
const { getAuth } = require('./gcp');

// Fields the API fills in itself; they must be stripped before re-creating a job.
const OUTPUT_ONLY = ['state', 'status', 'scheduleTime', 'lastAttemptTime', 'userUpdateTime'];
// Headers Scheduler sets on its own and refuses on create.
const BLOCKED_HEADER = /^(x-google-|x-appengine-|content-length$)/i;

function api() {
  return google.cloudscheduler({ version: 'v1', auth: getAuth() });
}

// "projects/p/locations/us-central1/jobs/my-job" → "my-job"
const jobId = (job) => job.name.split('/jobs/')[1];
const jobParent = (job) => job.name.split('/jobs/')[0];

async function listLocations(projectId) {
  const ids = [];
  let pageToken;
  do {
    const res = await api().projects.locations.list({ name: `projects/${projectId}`, pageToken });
    (res.data.locations || []).forEach((l) => ids.push(l.locationId));
    pageToken = res.data.nextPageToken;
  } while (pageToken);
  return ids;
}

async function listJobsIn(parent) {
  const jobs = [];
  let pageToken;
  do {
    const res = await api().projects.locations.jobs.list({ parent, pageToken, pageSize: 500 });
    jobs.push(...(res.data.jobs || []));
    pageToken = res.data.nextPageToken;
  } while (pageToken);
  return jobs;
}

// Scheduler jobs are regional, so sweep every region the API offers.
async function listAllJobs(projectId) {
  const locations = await listLocations(projectId);
  const failedLocations = [];
  const perLocation = await Promise.all(
    locations.map(async (loc) => {
      try {
        return await listJobsIn(`projects/${projectId}/locations/${loc}`);
      } catch (err) {
        console.log(`[scheduler] Could not list jobs in ${loc}: ${err.message}`);
        failedLocations.push(loc);
        return [];
      }
    })
  );
  const jobs = perLocation.flat().sort((a, b) => a.name.localeCompare(b.name));
  return { jobs, failedLocations };
}

// Copy of a job with only the fields jobs.create accepts.
function toRestorable(job) {
  const clean = JSON.parse(JSON.stringify(job));
  OUTPUT_ONLY.forEach((k) => delete clean[k]);
  const target = clean.httpTarget || clean.appEngineHttpTarget;
  if (target && target.headers) {
    for (const h of Object.keys(target.headers)) {
      const isDefaultAgent = h.toLowerCase() === 'user-agent' && target.headers[h] === 'Google-Cloud-Scheduler';
      if (BLOCKED_HEADER.test(h) || isDefaultAgent) delete target.headers[h];
    }
    if (!Object.keys(target.headers).length) delete target.headers;
  }
  return clean;
}

async function pauseJob(name) {
  await api().projects.locations.jobs.pause({ name, requestBody: {} });
}

async function deleteJob(name) {
  await api().projects.locations.jobs.delete({ name });
}

async function createJob(job) {
  await api().projects.locations.jobs.create({ parent: jobParent(job), requestBody: job });
}

async function jobExists(name) {
  try {
    await api().projects.locations.jobs.get({ name });
    return true;
  } catch (err) {
    if (err.code === 404) return false;
    throw err;
  }
}

module.exports = { jobId, listAllJobs, toRestorable, pauseJob, deleteJob, createJob, jobExists };
