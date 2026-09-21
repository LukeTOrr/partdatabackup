# scheduler-sunset (partdatabackup)

What:        On a set date, snapshots → pauses → deletes EVERY Cloud Scheduler job in celltech-internal-tools; restores them with one command
Runs:        Cloud Run job `scheduler-sunset` (us-central1), fired once by Cloud Scheduler job `scheduler-sunset-trigger`
Entry:       launch.js  (`teardown` default | `restore [snapshot object]`)
Inputs:      Cloud Scheduler API, all regions of celltech-internal-tools
Outputs:     gs://celltech-internal-tools-scheduler-snapshots/snapshots/<timestamp>.json + latest.json; JobLog heartbeat row
Secrets:     .env — see .env.example  |  Secret Manager: HEARTBEAT_SHEET_ID
Owner facts: Its own trigger is excluded from snapshot/delete and gets PAUSED after a teardown. Trigger time zone is America/Los_Angeles (noon Pacific, PDT/PST handled automatically).

---

## How it works

**Teardown**
1. Lists every scheduler job in every region, except `scheduler-sunset-trigger`.
2. Writes the full config of every job (cron, time zone, target, headers, body, auth SA, retry settings, original ENABLED/PAUSED state) to GCS. Then it reads the file back to verify it. If this step fails, nothing is touched.
3. Pauses every job.
4. Deletes every job.
5. Pauses its own trigger so it doesn't fire again next year.

If no jobs are found, `latest.json` is left alone, so a second run can't wipe the good snapshot.

**Restore:** Re-creates every job from `snapshots/latest.json` (or a named snapshot) in its original state. Jobs that already exist are skipped, so it's safe to re-run.

## First-time setup

See the Commands block in the chat handoff, or:

1. Create the Artifact Registry repo and the snapshot bucket.
2. Grant the service account roles: `cloudscheduler.admin`, `iam.serviceAccountUser`, and `run.invoker`, plus storage on the bucket.
3. Push to GitHub. Actions builds and deploys the job.
4. Create `scheduler-sunset-trigger`.

## Change the removal date

```
gcloud scheduler jobs update http scheduler-sunset-trigger --location=us-central1 --project=celltech-internal-tools --schedule="0 12 <DAY> <MONTH> *" --time-zone="America/Los_Angeles"
gcloud scheduler jobs resume scheduler-sunset-trigger --location=us-central1 --project=celltech-internal-tools
```

## Restore everything

```
gcloud run jobs execute scheduler-sunset --region=us-central1 --project=celltech-internal-tools --args=restore
```

## Troubleshooting

- Logs: `gcloud run jobs executions list --job=scheduler-sunset --region=us-central1`, then open the execution in the console.
- Check the JobLog sheet. The heartbeat message includes the snapshot path.
- List snapshots: `gcloud storage ls gs://celltech-internal-tools-scheduler-snapshots/snapshots/`
- A restore failure for one job usually means the service account can't act as that job's auth SA. Grant `iam.serviceAccountUser`.
