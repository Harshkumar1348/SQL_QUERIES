/**
 * Syncs data from "Query Output" sheet into "Data Dump" sheet.
 *
 * Optimized to use batch reads and writes instead of per-row API calls.
 * Original version made one setValues() call per row (~0.5-1s each).
 * This version collects all mutations in memory and writes them in
 * at most two bulk operations regardless of row count.
 */
function syncHandholdingData() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var querySheet = ss.getSheetByName("Query Output");
  var dumpSheet = ss.getSheetByName("Data Dump");

  var queryLastRow = querySheet.getLastRow();
  var dumpLastRow = dumpSheet.getLastRow();

  if (queryLastRow < 3 || dumpLastRow < 3) {
    Logger.log("Not enough data rows in one of the sheets.");
    return;
  }

  var COLS = 24;
  var queryData = querySheet.getRange(3, 2, queryLastRow - 2, COLS).getValues();
  var dumpData = dumpSheet.getRange(3, 2, dumpLastRow - 2, COLS).getValues();

  var today = new Date();
  var dumpModified = false;

  var dumpKeyMap = {};
  for (var i = 0; i < dumpData.length; i++) {
    var providerId = String(dumpData[i][0]).trim();
    var perfWeek = _formatDate(dumpData[i][5]);
    if (perfWeek !== null && providerId !== "") {
      dumpKeyMap[providerId + "|" + perfWeek] = i;
    }
  }

  var FIELDS_TO_COPY = [11, 12, 16, 17, 18, 19, 20, 21];
  var newRows = [];

  for (var q = 0; q < queryData.length; q++) {
    var queryRow = queryData[q];
    var qProviderId = String(queryRow[0]).trim();
    var qPerfWeek = _formatDate(queryRow[5]);

    if (qPerfWeek === null || qProviderId === "") continue;

    var key = qProviderId + "|" + qPerfWeek;

    if (dumpKeyMap.hasOwnProperty(key)) {
      var rowIdx = dumpKeyMap[key];
      var existing = dumpData[rowIdx];
      var changed = false;

      for (var f = 0; f < FIELDS_TO_COPY.length; f++) {
        var col = FIELDS_TO_COPY[f];
        if (existing[col] !== queryRow[col]) {
          existing[col] = queryRow[col];
          changed = true;
        }
      }

      if (changed) dumpModified = true;

    } else {
      var newRow = queryRow.slice();
      while (newRow.length < 22) newRow.push("");
      newRow[22] = today;
      while (newRow.length < COLS) newRow.push("");
      newRows.push(newRow);

      dumpKeyMap[key] = dumpData.length + newRows.length - 1;
    }
  }

  if (dumpModified) {
    dumpSheet.getRange(3, 2, dumpData.length, COLS).setValues(dumpData);
  }

  if (newRows.length > 0) {
    dumpSheet.getRange(dumpLastRow + 1, 2, newRows.length, COLS).setValues(newRows);
  }

  SpreadsheetApp.flush();

  Logger.log(
    "Sync complete — updated " + (dumpModified ? dumpData.length + " existing rows (batch)" : "0 rows") +
    ", appended " + newRows.length + " new rows."
  );
}

/** Returns 'YYYY-MM-DD' or null for unparseable dates. */
function _formatDate(d) {
  if (d instanceof Date && !isNaN(d.getTime())) {
    return d.getFullYear() + "-" +
      ("0" + (d.getMonth() + 1)).slice(-2) + "-" +
      ("0" + d.getDate()).slice(-2);
  }
  var parsed = new Date(d);
  if (isNaN(parsed.getTime())) return null;
  return parsed.getFullYear() + "-" +
    ("0" + (parsed.getMonth() + 1)).slice(-2) + "-" +
    ("0" + parsed.getDate()).slice(-2);
}
