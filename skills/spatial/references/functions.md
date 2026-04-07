# DuckDB Spatial Functions Reference

## Setup

```sql
INSTALL spatial; LOAD spatial;
-- For H3 hex binning:
INSTALL h3 FROM community; LOAD h3;
```

## Reading spatial files

| Format | Read method |
|--------|-------------|
| GeoJSON | `ST_Read('file.geojson')` |
| Shapefile | `ST_Read('file.shp')` |
| GeoPackage | `ST_Read('file.gpkg')` |
| FlatGeobuf | `ST_Read('file.fgb')` |
| KML | `ST_Read('file.kml')` |
| GPX | `ST_Read('file.gpx')` |
| GeoParquet | `FROM 'file.geoparquet'` (native, no ST_Read needed) |
| OSM PBF | `ST_ReadOSM('region.osm.pbf')` (multithreaded, tags as MAP column) |
| CSV with lat/lng | `SELECT *, ST_Point(lng, lat) AS geom FROM 'file.csv'` |

`ST_Read` uses GDAL internally and supports 50+ formats.

## Writing spatial files

```sql
COPY (SELECT * FROM ...) TO 'out.geojson' WITH (FORMAT GDAL, DRIVER 'GeoJSON');
COPY (SELECT * FROM ...) TO 'out.gpkg' WITH (FORMAT GDAL, DRIVER 'GPKG');
COPY (SELECT * FROM ...) TO 'out.shp' WITH (FORMAT GDAL, DRIVER 'ESRI Shapefile');
COPY (SELECT * FROM ...) TO 'out.fgb' WITH (FORMAT GDAL, DRIVER 'FlatGeobuf');
```

Set `geometry_always_xy = true` before writing to avoid axis order issues with KML or WGS84.

## Key functions

### Construction
| Function | Description |
|----------|-------------|
| `ST_Point(x, y)` | Create point from lon, lat |
| `ST_MakeEnvelope(xmin, ymin, xmax, ymax)` | Create bounding box rectangle |
| `ST_GeomFromText('POLYGON(...)')` | Parse WKT |
| `ST_GeomFromGeoJSON('{"type":...}')` | Parse GeoJSON |
| `ST_MakeLine(geom_array)` | Create line from points |

### Distance & proximity
| Function | Description |
|----------|-------------|
| `ST_Distance(a, b)` | Planar distance (units depend on CRS) |
| `ST_Distance_Spheroid(a, b)` | Geodesic distance in **meters** (WGS84) |
| `ST_DWithin(a, b, dist)` | Is planar distance ≤ dist? |
| `ST_DWithin_Spheroid(a, b, dist)` | Is geodesic distance ≤ dist meters? |

### Spatial relationships
| Function | Returns true when |
|----------|-------------------|
| `ST_Contains(a, b)` | a fully contains b |
| `ST_Within(a, b)` | a is fully within b |
| `ST_Intersects(a, b)` | a and b share any space |
| `ST_Covers(a, b)` | a covers b (no boundary distinction) |
| `ST_Disjoint(a, b)` | a and b share no space |
| `ST_Touches(a, b)` | a and b touch at boundary only |

### Measurement
| Function | Description |
|----------|-------------|
| `ST_Area(geom)` | Planar area |
| `ST_Area_Spheroid(geom)` | Geodesic area in **square meters** |
| `ST_Length(geom)` | Planar length of linestring |
| `ST_Length_Spheroid(geom)` | Geodesic length in **meters** |
| `ST_Perimeter(geom)` | Perimeter of polygon |
| `ST_NPoints(geom)` | Number of vertices |

### Transformation
| Function | Description |
|----------|-------------|
| `ST_Transform(geom, 'EPSG:from', 'EPSG:to')` | Reproject |
| `ST_Centroid(geom)` | Center point |
| `ST_Buffer(geom, dist)` | Buffer/expand geometry |
| `ST_Simplify(geom, tolerance)` | Simplify (Douglas-Peucker) |
| `ST_ConvexHull(geom)` | Convex hull |
| `ST_Union(a, b)` | Merge two geometries |
| `ST_Intersection(a, b)` | Intersection of two geometries |
| `ST_Difference(a, b)` | Subtract b from a |
| `ST_FlipCoordinates(geom)` | Swap x/y (for axis order issues) |

### Aggregation
| Function | Description |
|----------|-------------|
| `ST_Extent_Agg(geom)` | Bounding box of all geometries |
| `ST_Union_Agg(geom)` | Union of all geometries |
| `ST_Collect(array)` | Create GeometryCollection |

### Accessors
| Function | Description |
|----------|-------------|
| `ST_X(point)` | Get longitude |
| `ST_Y(point)` | Get latitude |
| `ST_GeometryType(geom)` | Type name (POINT, POLYGON, etc.) |
| `ST_AsText(geom)` | WKT representation |
| `ST_AsGeoJSON(geom)` | GeoJSON representation |
| `ST_XMin/XMax/YMin/YMax(geom)` | Bounding box coordinates |

## H3 hexagonal binning

H3 converts lat/lng to hexagonal cells at different resolutions. Great for density maps and hotspot analysis.

| Resolution | Avg edge | Use case |
|------------|----------|----------|
| 0 | ~1,107 km | Continental |
| 3 | ~59 km | Metropolitan regions |
| 5 | ~8 km | Cities |
| 7 | ~1.2 km | Neighborhoods |
| 9 | ~174 m | City blocks |
| 11 | ~25 m | Individual buildings |
| 13 | ~3.3 m | Parking spots |

Key functions:
```sql
-- Point to hex cell
h3_latlng_to_cell(lat, lng, resolution) → UBIGINT

-- Hex cell to center point
h3_cell_to_latlng(cell) → STRUCT(lat, lng)

-- Hex cell to polygon boundary (for visualization)
h3_cell_to_boundary_wkt(cell) → VARCHAR (WKT)

-- Ring of cells around a center
h3_grid_disk(cell, k) → UBIGINT[] (all cells within k rings)

-- Density example: count points per hex
SELECT h3_latlng_to_cell(lat, lng, 7) AS hex,
       count(*) AS cnt,
       h3_cell_to_boundary_wkt(hex) AS boundary
FROM my_points
GROUP BY hex
ORDER BY cnt DESC;
```

## Common patterns

### CSV with lat/lng → spatial queries
```sql
SELECT *, ST_Point(longitude, latitude) AS geom FROM 'data.csv';
```

### Distance matrix between all pairs
```sql
SELECT a.name, b.name,
       ST_Distance_Spheroid(a.geom, b.geom) AS dist_m
FROM locations a, locations b
WHERE a.name < b.name;
```

### Points inside polygons
```sql
SELECT p.name, z.zone_name
FROM points p, zones z
WHERE ST_Contains(z.geom, p.geom);
```

### Nearest neighbor (top-K per row)
```sql
SELECT a.name, b.name AS nearest,
       ST_Distance_Spheroid(a.geom, b.geom) AS dist_m
FROM locations a
CROSS JOIN LATERAL (
    SELECT name, geom FROM targets b
    ORDER BY ST_Distance_Spheroid(a.geom, b.geom)
    LIMIT 3
) b;
```
