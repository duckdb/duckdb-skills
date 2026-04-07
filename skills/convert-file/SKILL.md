---
name: convert-file
description: >
  Convert any data file to another format: CSV, Parquet, JSON, Excel, GeoJSON, and more.
  Use when the user says "convert to parquet", "save as xlsx", "export as JSON", "make this a CSV",
  "turn into parquet", or any variation of format-to-format conversion for data files.
  Also triggers when the user wants to write Parquet, Excel, or other binary formats that Claude cannot produce natively.
argument-hint: <input-file> [output-file]
allowed-tools: Bash
---

You are helping the user convert a data file from one format to another using DuckDB.

Input file: `$0`
Output file: `${1:-}`

## Step 1 — Resolve input and output

**Input**: `$0`. If it's a bare filename (no `/`), resolve to a full path with `find "$PWD" -name "$0" -not -path '*/.git/*' 2>/dev/null | head -1`.

**Output**: If `$1` is provided, use it as the output path. If not, default to the same stem as the input with a `.parquet` extension (e.g., `data.csv` → `data.parquet`).

Infer the output format from the output file extension:

| Extension | Format clause |
|---|---|
| `.parquet`, `.pq` | *(default, no clause needed)* |
| `.csv` | `(FORMAT csv, HEADER)` |
| `.tsv` | `(FORMAT csv, HEADER, DELIMITER '\t')` |
| `.json` | `(FORMAT json, ARRAY true)` |
| `.jsonl`, `.ndjson` | `(FORMAT json, ARRAY false)` |
| `.xlsx` | `(FORMAT xlsx)` — requires `INSTALL excel; LOAD excel;` |
| `.geojson` | `(FORMAT GDAL, DRIVER 'GeoJSON')` — requires `LOAD spatial;` |
| `.gpkg` | `(FORMAT GDAL, DRIVER 'GPKG')` — requires `LOAD spatial;` |
| `.shp` | `(FORMAT GDAL, DRIVER 'ESRI Shapefile')` — requires `LOAD spatial;` |

## Step 2 — Convert

Run a single DuckDB command. Prepend extension loads as needed based on both the input and output formats.

```bash
duckdb -c "
<EXTENSION_LOADS>
COPY (FROM '<INPUT_PATH>') TO '<OUTPUT_PATH>' <FORMAT_CLAUSE>;
"
```

For remote inputs (`s3://`, `https://`, etc.), prepend the same protocol setup as `read-file`:

| Protocol | Prepend |
|---|---|
| `s3://` | `LOAD httpfs; CREATE SECRET (TYPE S3, PROVIDER credential_chain);` |
| `gs://` / `gcs://` | `LOAD httpfs; CREATE SECRET (TYPE GCS, PROVIDER credential_chain);` |
| `https://` / `http://` | `LOAD httpfs;` |

**If the user mentions partitioning** (e.g., "partition by year"), add `PARTITION_BY (col)` to the format clause. This only works with Parquet and CSV output.

**If the user mentions compression** (e.g., "use zstd"), add `CODEC 'zstd'` for Parquet output.

## Step 3 — Report

On success, report:
- Input file and detected format
- Output file, format, and size (`ls -lh`)
- Row count if quick to compute

On failure:
- **`duckdb: command not found`** → delegate to `/duckdb-skills:install-duckdb`
- **Missing extension** → install it and retry
- **Input parse error** → suggest the user check the input format or try `/duckdb-skills:read-file` first to inspect it
