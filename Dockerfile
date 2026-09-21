# Only needed when this job is promoted to Cloud Run (see DEV-STANDARD.md §9).
# Puppeteer needs Chromium's system deps — the official image ships them all.
FROM ghcr.io/puppeteer/puppeteer:22.0.0

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

# Cloud Run jobs: no port needed. HEADLESS must be true in the cloud.
ENV HEADLESS=true

CMD ["node", "launch.js"]
