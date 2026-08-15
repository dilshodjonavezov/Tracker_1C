import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath =
  "/Users/macone/Downloads/gps_report_2026-07-28_2026-07-28.xlsx";
const outputDir =
  "/Users/macone/Desktop/Tracker_1C/outputs/inspect-phone-report";

const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const overview = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 20000,
  tableMaxRows: 200,
  tableMaxCols: 20,
  tableMaxCellChars: 160,
});
await fs.writeFile(`${outputDir}/inspection.ndjson`, overview.ndjson, "utf8");

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "formula error scan",
});
await fs.writeFile(`${outputDir}/errors.ndjson`, errors.ndjson, "utf8");

const preview = await workbook.render({
  sheetName: "Отчёт GPS",
  autoCrop: "all",
  scale: 1,
  format: "png",
});
await fs.writeFile(
  `${outputDir}/preview.png`,
  new Uint8Array(await preview.arrayBuffer()),
);

console.log(overview.ndjson);
