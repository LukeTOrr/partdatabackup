// Google Sheets helpers — the appendData.js you've copied into 20 projects,
// finished properly: auth from env (not a loose configuration.json), plus the
// header-name column lookup you already use everywhere in Apps Script.
//
// Auth: set GOOGLE_SA_KEY_FILE in .env to the path of a service-account JSON
// (keep the file OUTSIDE the project folder, e.g. C:\Users\PCUser\.keys\).
const { google } = require('googleapis');
const path = require('path');

let gsapi = null;
function sheetsClient() {
  if (gsapi) return gsapi;
  const keyFile = process.env.GOOGLE_SA_KEY_FILE;
  const scopes = ['https://www.googleapis.com/auth/spreadsheets'];
  // No key file (Cloud Run) → fall back to the attached service account.
  const auth = keyFile
    ? new google.auth.GoogleAuth({ keyFile: path.resolve(keyFile), scopes })
    : new google.auth.GoogleAuth({ scopes });
  gsapi = google.sheets({ version: 'v4', auth });
  return gsapi;
}

// Read a whole tab (or an A1 range) → 2D array of values.
async function readSheet(spreadsheetId, range) {
  const res = await sheetsClient().spreadsheets.values.get({ spreadsheetId, range });
  return res.data.values || [];
}

// Append rows to the bottom of a tab. rows = [[...], [...]]
async function appendRows(spreadsheetId, tab, rows) {
  if (!rows.length) return;
  await sheetsClient().spreadsheets.values.append({
    spreadsheetId,
    range: tab,
    valueInputOption: 'USER_ENTERED',
    insertDataOption: 'INSERT_ROWS',
    resource: { values: rows },
  });
}

// Overwrite an exact range. values = 2D array shaped to the range.
async function writeRange(spreadsheetId, range, values) {
  await sheetsClient().spreadsheets.values.update({
    spreadsheetId,
    range,
    valueInputOption: 'USER_ENTERED',
    resource: { values },
  });
}

// Column lookup by HEADER NAME, never by letter (your standing rule).
// headerRow is 0-indexed within `data` (facility sheets: headers on row 2 → pass 1).
// Returns the column index, or -1 (log-and-skip, don't throw — caller decides).
function colIndex(data, headerName, headerRow = 0) {
  const headers = data[headerRow] || [];
  const i = headers.findIndex(
    (h) => h != null && h.toString().trim().toLowerCase() === headerName.trim().toLowerCase()
  );
  if (i === -1) console.log(`[sheets] Column "${headerName}" not found on header row ${headerRow + 1}`);
  return i;
}

module.exports = { readSheet, appendRows, writeRange, colIndex };
