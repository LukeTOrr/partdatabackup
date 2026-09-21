// Shared Google Cloud auth.
// Locally: GOOGLE_SA_KEY_FILE in .env points at a service-account JSON.
// On Cloud Run: leave it unset and the job's attached service account is used (ADC).
const { google } = require('googleapis');
const path = require('path');

const SCOPES = ['https://www.googleapis.com/auth/cloud-platform'];

let auth = null;
function getAuth() {
  if (auth) return auth;
  const keyFile = process.env.GOOGLE_SA_KEY_FILE;
  auth = new google.auth.GoogleAuth(
    keyFile ? { keyFile: path.resolve(keyFile), scopes: SCOPES } : { scopes: SCOPES }
  );
  return auth;
}

module.exports = { getAuth };
