FROM node:20-slim

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

# ENTRYPOINT (not CMD) so `gcloud run jobs execute --args=restore` appends the mode
# instead of replacing the whole command.
ENTRYPOINT ["node", "launch.js"]
