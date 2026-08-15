import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath =
  "/Users/macone/Desktop/Tracker_1C/outputs/019f/location_report_preview.xlsx";
const outputDir =
  "/Users/macone/Desktop/Tracker_1C/outputs/verify-device-events";

const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const overview = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 12000,
  tableMaxRows: 12,
  tableMaxCols: 16,
  tableMaxCellChars: 180,
});
await fs.writeFile(`${outputDir}/inspection.ndjson`, overview.ndjson, "utf8");

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "formula error scan",
});
await fs.writeFile(`${outputDir}/errors.ndjson`, errors.ndjson, "utf8");

for (const sheetName of ["Отчёт GPS", "События устройства"]) {
  const preview = await workbook.render({
    sheetName,
    autoCrop: "all",
    scale: 1,
    format: "png",
  });
  const fileName =
    sheetName === "Отчёт GPS" ? "gps-preview.png" : "events-preview.png";
  await fs.writeFile(
    `${outputDir}/${fileName}`,
    new Uint8Array(await preview.arrayBuffer()),
  );
}

console.log(overview.ndjson);
