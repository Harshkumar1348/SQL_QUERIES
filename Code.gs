function syncHandholdingData() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const querySheet = ss.getSheetByName("Query Output");
  const dumpSheet = ss.getSheetByName("Data Dump");

  const QUERY_COLS = 21; // B:V (includes Late Show Count at M)
  const DUMP_COLS = 23; // B:X (includes Date Added at W, Key at X)
  const DATE_ADDED_INDEX = 21; // Column W

  // Now pulling 21 columns (B to V) from Query Output
  const queryRowCount = Math.max(0, querySheet.getLastRow() - 2);
  const dumpRowCount = Math.max(0, dumpSheet.getLastRow() - 2);

  const queryData =
    queryRowCount > 0
      ? querySheet.getRange(3, 2, queryRowCount, QUERY_COLS).getValues() // B3:V
      : [];
  const dumpData =
    dumpRowCount > 0
      ? dumpSheet.getRange(3, 2, dumpRowCount, DUMP_COLS).getValues() // B3:X
      : [];

  const formatDate = (d) => {
    const parsed = new Date(d);
    if (isNaN(parsed)) return "Invalid";
    return (
      parsed.getFullYear() +
      "-" +
      String(parsed.getMonth() + 1).padStart(2, "0") +
      "-" +
      String(parsed.getDate()).padStart(2, "0")
    );
  };

  const today = new Date();

  // Step 1: Build a key map of provider_id|perf_week for existing dump rows
  const dumpKeyMap = new Map();
  dumpData.forEach((row, i) => {
    const providerId = String(row[0]).trim(); // Column B
    const perfWeek = formatDate(row[5]); // Column G
    if (perfWeek !== "Invalid" && providerId) {
      const key = `${providerId}|${perfWeek}`;
      dumpKeyMap.set(key, i);
    }
  });

  // Step 2: Loop through Query Output and sync with Data Dump
  queryData.forEach((queryRow) => {
    const providerId = String(queryRow[0]).trim(); // Column B
    const perfWeek = formatDate(queryRow[5]); // Column G
    const key = `${providerId}|${perfWeek}`;

    if (perfWeek === "Invalid" || !providerId) {
      Logger.log(
        `❌ Skipped row with invalid provider or date: ${providerId}, ${perfWeek}`
      );
      return;
    }

    if (dumpKeyMap.has(key)) {
      // Existing row – update late show + status fields
      const rowIndex = dumpKeyMap.get(key);
      const existingRow = dumpData[rowIndex];

      existingRow[11] = queryRow[11]; // Late Show Count (M)
      existingRow[15] = queryRow[15]; // Rating Errors (Q)
      existingRow[16] = queryRow[16]; // PAF Count (R)
      existingRow[17] = queryRow[17]; // Leaves (S)
      existingRow[18] = queryRow[18]; // Partner Week Status (T)
      existingRow[19] = queryRow[19]; // Bad Rated Jobs (U)
      existingRow[20] = queryRow[20]; // PAF Request IDs (V)

      while (existingRow.length < DUMP_COLS) existingRow.push("");
      dumpSheet.getRange(rowIndex + 3, 2, 1, DUMP_COLS).setValues([existingRow]);
      Logger.log(`✅ Updated row ${rowIndex + 3} for ${providerId} | ${perfWeek}`);
    } else {
      // New row – append full queryRow, plus today’s date in col W
      const newRow = [...queryRow];
      while (newRow.length < DUMP_COLS) newRow.push("");
      newRow[DATE_ADDED_INDEX] = today; // Column W (Date Added)

      const insertAt = dumpSheet.getLastRow() + 1;
      dumpSheet.getRange(insertAt, 2, 1, DUMP_COLS).setValues([newRow]);
      Logger.log(`➕ Added new row at ${insertAt} for ${providerId} | ${perfWeek}`);
    }
  });

  SpreadsheetApp.flush();
}
