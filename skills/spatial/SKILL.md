---
name: spatial
description: >
  Answer questions about spatial data using DuckDB. Use when the user mentions locations,
  coordinates, lat/lng, distances, maps, addresses, "near", "within", "closest", geographic
  names, or spatial file formats (GeoJSON, Shapefile, GeoPackage, GPX, GeoParquet). Also
  triggers when the user wants to find places, buildings, or roads — Overture Maps provides
  free global data on S3 with zero API keys. Handles spatial joins, distance calculations,
  containment checks, density analysis, and format conversions for geographic data.
argument-hint: <question or file> [additional context]
allowed-tools: Bash
---

You are answering spatial questions using DuckDB's spatial extension and, when needed, Overture Maps as a free global data source.

Question or file: `$0`
Additional context: `${1:-}`

## Step 1 — Understand what the user needs

Classify the question:

| Pattern | Data source | Key functions |
|---------|-------------|---------------|
| "Find X near Y" (no user file) | Overture Maps on S3 | `ST_Distance_Spheroid`, bbox filtering |
| "How far between A and B" | Geocode or user data | `ST_Distance_Spheroid` |
| "Which points fall inside polygons" | User files | `ST_Contains` |
| "Analyze this GeoJSON/Shapefile/GPX" | User file | `ST_Read`, measurement functions |
| "Show density/hotspots" | User or Overture data | H3 hex binning |
| "Convert to GeoJSON/GeoPackage" | User file | `COPY TO (FORMAT GDAL)` |
| "Count buildings/roads in area" | Overture Maps | bbox filtering + aggregation |

If the question involves real-world places, POIs, buildings, roads, or boundaries and the user hasn't provided a file, use **Overture Maps** — read `references/overture.md` for S3 paths and schema.

For spatial function syntax, read `references/functions.md`.

## Step 2 — Write and run the query

Always start with:
```sql
LOAD spatial;
SET geometry_always_xy = true;
```

Add extensions as needed:
- Overture/remote data: `LOAD httpfs; CREATE SECRET (TYPE S3, PROVIDER config, REGION 'us-west-2');`
- H3 hex binning: `INSTALL h3 FROM community; LOAD h3;`

### Key principles

**bbox filtering first** — When querying Overture, always filter on `bbox.xmin/xmax/ymin/ymax` before any spatial function. This uses Parquet predicate pushdown and avoids downloading the full dataset.

**Always set `geometry_always_xy = true`** — This ensures all spatial functions interpret coordinates as longitude, latitude (the standard for Overture, GeoJSON, and most data sources). Without it, spheroid functions assume latitude first and return wrong results.

**Use spheroid functions for real-world distances** — `ST_Distance_Spheroid` returns meters on the WGS84 ellipsoid. Plain `ST_Distance` uses planar coordinates and gives meaningless results for lat/lng. **Important:** spheroid functions (`ST_Distance_Spheroid`, `ST_Area_Spheroid`, etc.) require `POINT_2D` inputs, not generic `GEOMETRY`. Overture geometry columns are typed `GEOMETRY('OGC:CRS84')` and cannot be cast directly. Extract coordinates first:
```sql
ST_Point(ST_X(geometry), ST_Y(geometry))::POINT_2D
```

**CSV with lat/lng needs conversion** — `ST_Point(longitude, latitude)` (longitude first). This is the most common gotcha.

Run the query in a single bash call:

```bash
duckdb -c "
LOAD spatial;
<ADDITIONAL_SETUP>
<YOUR_QUERY>
"
```

## Step 3 — Present results

- For tabular results: show the data directly
- For spatial results: consider exporting to GeoJSON for visualization (`COPY TO 'result.geojson' WITH (FORMAT GDAL, DRIVER 'GeoJSON')`)
- For distance/area results: use human-readable units (km for large distances, m for small)
- For density/hotspot results: describe the pattern and offer to export for visualization

If the query fails:
- **`duckdb: command not found`** → delegate to `/duckdb-skills:install-duckdb`
- **Missing extension** → `INSTALL spatial; LOAD spatial;` or `INSTALL h3 FROM community; LOAD h3;`
- **S3 access denied** → suggest checking AWS credentials
- **No results with Overture** → widen the bbox, check the category spelling, or try a broader search
