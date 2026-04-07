---
name: s3-explore
description: >
  Explore and query data on S3, Cloudflare R2, GCS, MinIO, or any S3-compatible storage.
  Use when the user mentions an s3://, r2://, gs://, or gcs:// URL, asks "what's in this bucket",
  wants to list remote files, preview remote Parquet/CSV/JSON, or query data on object storage
  without downloading it. Also triggers when the user wants to know the size, schema, or row count
  of remote datasets.
argument-hint: <s3-url> [question about the data]
allowed-tools: Bash
---

You are helping the user explore data on remote object storage using DuckDB.

URL: `$0`
Question: `${1:-list and describe what's there}`

## Step 1 — Detect provider and set up credentials

Based on the URL or user context, prepend the appropriate secret configuration:

| Provider | URL patterns | Secret setup |
|---|---|---|
| **AWS S3** | `s3://` | `CREATE SECRET (TYPE S3, PROVIDER credential_chain);` |
| **Cloudflare R2** | `r2://`, `s3://` with R2 endpoint | `CREATE SECRET (TYPE R2, PROVIDER credential_chain);` |
| **GCS** | `gs://`, `gcs://` | `CREATE SECRET (TYPE GCS, PROVIDER credential_chain);` |
| **MinIO / custom** | `s3://` with custom endpoint | `CREATE SECRET (TYPE S3, KEY_ID '...', SECRET '...', ENDPOINT '...', USE_SSL true);` |

For R2, if the user provides an account ID, the endpoint is `<account_id>.r2.cloudflarestorage.com`. R2 URLs like `r2://bucket/path` should be rewritten to `s3://bucket/path` with the R2 secret.

For public buckets (e.g., Overture Maps, AWS open data), no secret is needed — skip this step.

Always prepend:
```sql
LOAD httpfs;
```

## Step 2 — Determine what the URL points to

If the URL looks like a **directory or bucket** (no file extension, or ends with `/`), list its contents with sizes:

```bash
duckdb -c "
LOAD httpfs;
<SECRET_SETUP>
SELECT filename, (size / 1024 / 1024)::DECIMAL(10,1) AS size_mb, last_modified
FROM read_blob('<URL>/*')
ORDER BY filename
LIMIT 50;
"
```

Note: only select `filename`, `size`, `last_modified` — never select `content`, which would download the actual files.

If the URL points to a **specific file or glob pattern** (has a file extension or contains `*`), preview it:

```bash
duckdb -c "
LOAD httpfs;
<SECRET_SETUP>
DESCRIBE FROM '<URL>';
SELECT count(*) AS row_count FROM '<URL>';
FROM '<URL>' LIMIT 20;
"
```

For **Parquet files**, get row counts and sizes from metadata (no data download):

```bash
duckdb -c "
LOAD httpfs;
<SECRET_SETUP>
SELECT file_name,
       sum(row_group_num_rows) AS total_rows,
       (sum(row_group_compressed_bytes) / 1024 / 1024)::DECIMAL(10,1) AS compressed_mb
FROM parquet_metadata('<URL>')
GROUP BY file_name;
"
```

## Step 3 — Answer the question

Using the listing, schema, or sample data, answer:

`${1:-list and describe what's there}`

If the user asks an analytical question (e.g., "how many rows match X"), write and run the appropriate SQL query. DuckDB pushes predicates down into Parquet on S3, so filtering is efficient even on large remote datasets.

## Error handling

- **`duckdb: command not found`** → delegate to `/duckdb-skills:install-duckdb`
- **Access denied / 403** → suggest the user check credentials: `aws configure`, environment variables, or provide explicit key/secret
- **Bucket not found / 404** → check the URL and region
- **Timeout on large listing** → suggest narrowing the glob pattern or adding a prefix
