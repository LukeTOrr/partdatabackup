// Snapshot storage in a GCS bucket (Cloud Run's disk is wiped after every run).
// Each teardown writes snapshots/<timestamp>.json AND snapshots/latest.json.
const { google } = require('googleapis');
const { getAuth } = require('./gcp');

const PREFIX = 'snapshots';

function api() {
  return google.storage({ version: 'v1', auth: getAuth() });
}

async function writeObject(bucket, name, obj) {
  await api().objects.insert({
    bucket,
    name,
    media: { mimeType: 'application/json', body: JSON.stringify(obj, null, 2) },
  });
}

async function readObject(bucket, name) {
  const res = await api().objects.get({ bucket, object: name, alt: 'media' }, { responseType: 'text' });
  return typeof res.data === 'string' ? JSON.parse(res.data) : res.data;
}

// Writes the snapshot, then reads it back to prove it landed intact.
// Throws if anything is off, so the caller never deletes without a good copy.
async function saveSnapshot(bucket, snapshot) {
  const stamp = snapshot.createdAt.replace(/[:.]/g, '-');
  const dated = `${PREFIX}/${stamp}.json`;
  const latest = `${PREFIX}/latest.json`;

  await writeObject(bucket, dated, snapshot);
  const check = await readObject(bucket, dated);
  if (!check.jobs || check.jobs.length !== snapshot.jobs.length) {
    throw new Error(`Snapshot verify failed for gs://${bucket}/${dated}`);
  }
  await writeObject(bucket, latest, snapshot);
  return { dated: `gs://${bucket}/${dated}`, latest: `gs://${bucket}/${latest}` };
}

async function loadSnapshot(bucket, name = `${PREFIX}/latest.json`) {
  return readObject(bucket, name);
}

module.exports = { saveSnapshot, loadSnapshot };
