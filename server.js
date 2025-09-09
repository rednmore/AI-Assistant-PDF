import express from "express";
import multer from "multer";
import { exec } from "child_process";
import { promisify } from "util";
import fs from "fs";
import path from "path";
import os from "os";
import tmp from "tmp";

const app = express();
const upload = multer({ limits: { fileSize: 200 * 1024 * 1024 } }); // limite 200 Mo
const pexec = promisify(exec);

function b64(buf) {
  return Buffer.from(buf).toString("base64");
}
function fromB64(s) {
  return Buffer.from(s, "base64");
}

// Middleware sécurité (optionnel si vous ajoutez API_TOKEN dans Render)
app.use((req, res, next) => {
  const token = req.header("x-api-token");
  if (process.env.API_TOKEN && token !== process.env.API_TOKEN) {
    return res.status(401).json({ error: "unauthorized" });
  }
  next();
});

// ==== /split ====
// Input : multipart form-data file=<pdf>
// Output : { pages: [ {index, pdf_b64} ] }
app.post("/split", upload.single("file"), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: "file required" });
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "split-"));
  const inPath = path.join(tmpDir, "in.pdf");
  fs.writeFileSync(inPath, req.file.buffer);

  // split chaque page avec pdfcpu
  await pexec(`pdfcpu split -q "${inPath}" "${tmpDir}/page"`);

  const files = fs
    .readdirSync(tmpDir)
    .filter((f) => f.endsWith(".pdf"))
    .sort();

  const pages = files.map((f, i) => {
    const buf = fs.readFileSync(path.join(tmpDir, f));
    return { index: i + 1, pdf_b64: b64(buf) };
  });

  res.json({ pages });
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

// ==== /text ====
// Input : { pages:[{index,pdf_b64}], ocrLang? }
// Output : { texts:[{index,text}] }
app.use(express.json({ limit: "200mb" }));
app.post("/text", async (req, res) => {
  const { pages, ocrLang = "eng+fra+deu" } = req.body || {};
  if (!pages?.length) return res.status(400).json({ error: "pages required" });

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "text-"));
  const results = [];

  for (const p of pages) {
    const pdfPath = path.join(tmpDir, `p${p.index}.pdf`);
    fs.writeFileSync(pdfPath, fromB64(p.pdf_b64));

    const txtPath = path.join(tmpDir, `p${p.index}.txt`);
    await pexec(`pdftotext -layout "${pdfPath}" "${txtPath}" || true`);

    let text = fs.existsSync(txtPath)
      ? fs.readFileSync(txtPath, "utf8")
      : "";

    if (!text || text.trim().length < 10) {
      // fallback OCR
      const imgPrefix = path.join(tmpDir, `p${p.index}`);
      await pexec(`pdftoppm -r 200 -gray "${pdfPath}" "${imgPrefix}"`);
      await pexec(
        `tesseract "${imgPrefix}-1.pgm" "${imgPrefix}" -l ${ocrLang} --psm 6`
      );
      text = fs.readFileSync(`${imgPrefix}.txt`, "utf8");
    }

    results.push({ index: p.index, text: text.trim() });
  }

  res.json({ texts: results });
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

// ==== /merge ====
// Input : { pages:[{index,pdf_b64}] }
// Output : { pdf_b64 }
app.post("/merge", async (req, res) => {
  const { pages } = req.body || {};
  if (!pages?.length) return res.status(400).json({ error: "pages required" });

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "merge-"));
  const inputs = [];

  for (const p of pages) {
    const f = path.join(tmpDir, `p${p.index}.pdf`);
    fs.writeFileSync(f, fromB64(p.pdf_b64));
    inputs.push(`"${f}"`);
  }

  const outPath = path.join(tmpDir, "out.pdf");
  await pexec(`pdfcpu merge -q "${outPath}" ${inputs.join(" ")}`);

  const buf = fs.readFileSync(outPath);
  res.json({ pdf_b64: b64(buf) });
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

// ==== Launch ====
const PORT = process.env.PORT || 8088;
app.listen(PORT, () => console.log(`PDF service running on port ${PORT}`));
