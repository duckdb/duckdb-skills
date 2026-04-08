# Overture Maps Reference

Overture Maps is a free, open global dataset — POIs, buildings, roads, boundaries — distributed as GeoParquet on S3. No API keys, no downloads, no registration.

## Access

```sql
LOAD httpfs;
LOAD spatial;
CREATE SECRET (TYPE S3, PROVIDER config, REGION 'us-west-2');
```

## S3 paths

Use the STAC catalog at `https://stac.overturemaps.org/catalog.json` to find the latest release. As of 2026-03-18, the latest release is `2026-03-18.0`.

Base path: `s3://overturemaps-us-west-2/release/<RELEASE>/`

| Theme | Type | Path suffix |
|-------|------|-------------|
| Places (POIs) | place | `theme=places/type=place/*` |
| Buildings | building | `theme=buildings/type=building/*` |
| Transportation | segment | `theme=transportation/type=segment/*` |
| Divisions (admin boundaries) | division | `theme=divisions/type=division/*` |
| Division areas (polygons) | division_area | `theme=divisions/type=division_area/*` |
| Addresses | address | `theme=addresses/type=address/*` |
| Base (land, water, land_use) | various | `theme=base/type=land/*` etc. |

## Efficient querying — bbox filtering

Overture files are partitioned by bounding box. Use `bbox.*` columns for predicate pushdown — this avoids downloading the entire dataset:

```sql
FROM read_parquet('s3://overturemaps-us-west-2/release/2026-03-18.0/theme=places/type=place/*')
WHERE bbox.xmin > -74.00 AND bbox.xmax < -73.97
  AND bbox.ymin > 40.74 AND bbox.ymax < 40.76
```

Always filter on bbox first, then apply additional filters.

## Schema: Places

| Field | Type | Description |
|-------|------|-------------|
| `id` | VARCHAR | Unique identifier |
| `geometry` | GEOMETRY | Point location |
| `bbox.xmin/xmax/ymin/ymax` | DOUBLE | Bounding box (for pushdown) |
| `names.primary` | VARCHAR | Primary name |
| `categories.primary` | VARCHAR | Primary category (e.g., `coffee_shop`, `restaurant`, `hospital`) |
| `categories.alternate` | VARCHAR[] | Additional categories |
| `confidence` | DOUBLE | 0–1 confidence score |
| `addresses[1].freeform` | VARCHAR | Full address text |
| `addresses[1].locality` | VARCHAR | City/town |
| `addresses[1].country` | VARCHAR | Country code |
| `websites` | VARCHAR[] | URLs |
| `phones` | VARCHAR[] | Phone numbers |
| `brand.names.primary` | VARCHAR | Brand name |

## Schema: Buildings

| Field | Type | Description |
|-------|------|-------------|
| `id` | VARCHAR | Unique identifier |
| `geometry` | GEOMETRY | Polygon footprint |
| `names.primary` | VARCHAR | Building name (often null) |
| `class` | VARCHAR | Building class |
| `height` | DOUBLE | Height in meters |
| `num_floors` | INTEGER | Number of floors |
| `roof_shape` | VARCHAR | Roof shape |

## Schema: Divisions

| Field | Type | Description |
|-------|------|-------------|
| `id` | VARCHAR | Unique identifier |
| `geometry` | GEOMETRY | Point (representative location) |
| `names.primary` | VARCHAR | Division name |
| `subtype` | VARCHAR | `country`, `region`, `county`, `locality`, etc. |
| `admin_level` | INTEGER | Hierarchy level |
| `population` | INTEGER | Population |
| `country` | VARCHAR | ISO 3166-1 alpha-2 |

## Schema: Division Areas (boundaries)

| Field | Type | Description |
|-------|------|-------------|
| `id` | VARCHAR | Unique identifier |
| `geometry` | GEOMETRY | MultiPolygon boundary |
| `division_id` | VARCHAR | Links to division |
| `names.primary` | VARCHAR | Area name |
| `subtype` | VARCHAR | Same as divisions |
| `country` | VARCHAR | ISO 3166-1 alpha-2 |

## Schema: Transportation Segments

| Field | Type | Description |
|-------|------|-------------|
| `id` | VARCHAR | Unique identifier |
| `geometry` | GEOMETRY | LineString centerline |
| `names.primary` | VARCHAR | Road name |
| `class` | VARCHAR | Road class (motorway, primary, secondary, tertiary, residential, etc.) |
| `subtype` | VARCHAR | road, rail, water |
| `speed_limits` | STRUCT[] | Speed limit rules |

## Common queries

### Find places by category near a point
```sql
SELECT names.primary, categories.primary, confidence,
       ST_Distance_Spheroid(
         ST_Point(ST_X(geometry), ST_Y(geometry))::POINT_2D,
         ST_Point(-73.985, 40.748)::POINT_2D
       ) AS dist_m
FROM read_parquet('s3://overturemaps-us-west-2/release/2026-03-18.0/theme=places/type=place/*')
WHERE bbox.xmin BETWEEN -74.01 AND -73.96
  AND bbox.ymin BETWEEN 40.72 AND 40.77
  AND categories.primary = 'coffee_shop'
ORDER BY dist_m
LIMIT 10;
```

### Count buildings in a city
```sql
SELECT count(*) AS buildings
FROM read_parquet('s3://overturemaps-us-west-2/release/2026-03-18.0/theme=buildings/type=building/*')
WHERE bbox.xmin BETWEEN -122.75 AND -122.55
  AND bbox.ymin BETWEEN 45.45 AND 45.60;
```

### Join user data with Overture
```sql
-- Find nearest Overture place to each row in user's CSV
SELECT u.*, p.names.primary AS nearest_place, p.categories.primary AS category,
       ST_Distance_Spheroid(
         ST_Point(u.longitude, u.latitude)::POINT_2D,
         ST_Point(ST_X(p.geometry), ST_Y(p.geometry))::POINT_2D
       ) AS dist_m
FROM 'user_locations.csv' u
CROSS JOIN LATERAL (
    SELECT * FROM read_parquet('s3://overturemaps-us-west-2/release/2026-03-18.0/theme=places/type=place/*')
    WHERE bbox.xmin BETWEEN u.longitude - 0.01 AND u.longitude + 0.01
      AND bbox.ymin BETWEEN u.latitude - 0.01 AND u.latitude + 0.01
    ORDER BY ST_Distance_Spheroid(
      ST_Point(ST_X(geometry), ST_Y(geometry))::POINT_2D,
      ST_Point(u.longitude, u.latitude)::POINT_2D
    )
    LIMIT 1
) p;
```
