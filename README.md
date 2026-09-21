# ProjectName

What:        one sentence — what business problem this solves
Runs:        Task Scheduler daily 6:00am  |  Cloud Run job  |  manual
Entry:       run.bat → launch.js
Inputs:      (portal/page/report this reads, sheet ranges it reads)
Outputs:     (sheet/tab it writes, files it produces, emails it sends)
Secrets:     .env — see .env.example  |  Secret Manager: (names, see secrets-registry.md)
Owner facts: (header row number, delimiter quirks, which page selectors came from + date)

---

## Setup (new machine)

```
git clone <repo-url>
cd ProjectName
npm install
copy .env.example .env    (then fill in values)
node launch.js
```

## Steps

1. `scripts/download.js` — ...
2. `scripts/consolidate.js` — ...
3. `scripts/upload.js` — ...

## Troubleshooting

- Check `data\run.log` for the last scheduled run.
- Check the JobLog sheet — did the heartbeat row say FAIL, and with what message?
- If a selector broke: selectors documented above came from <page URL>; re-derive
  with DevTools and update `scripts/<step>.js`.
