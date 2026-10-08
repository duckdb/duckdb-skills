-- setup.sql: the dev DuckDB. launchd runs `duckdb ~/.duck/dev.duckdb -init setup.sql`; a second instance is the same
-- file with DEV_QUACK_PORT / DEV_QUACKAPI_PORT / DEV_MCP_PORT set. Idempotent definitions live in live.sql,
-- schedules in cron.sql. Order matters: secrets settings precede every LOAD; the lock is last.
SET VARIABLE server_dir = coalesce(nullif(getenv('SERVER_DIR'), ''), '/Users/aloksubbarao/duckdb-skills');
SET GLOBAL home_directory = getenv('HOME');
SET GLOBAL extension_directory = getenv('HOME') || '/.duck/extensions';
SET GLOBAL secret_directory = getenv('HOME') || '/.duck/secrets';

-- Start this instance's Quack door before the ordered source phases. Each phase is then sent as
-- one complete body to this instance, so the CLI never needs a shared bootstrap rendezvous file.
INSTALL quack; LOAD quack;
SET VARIABLE quack_uri = 'quack:localhost:' || coalesce(nullif(getenv('DEV_QUACK_PORT'), ''), '9494');
SET VARIABLE quackapi_port = coalesce(nullif(getenv('DEV_QUACKAPI_PORT'), ''), '9495')::INTEGER;
SET VARIABLE mcp_port = coalesce(nullif(getenv('DEV_MCP_PORT'), ''), '9496')::INTEGER;
SET VARIABLE otlp_dir = getenv('HOME') || '/.duck/otlp';
CALL quack_identify(name := 'dev', hostname := 'localhost', region := 'local', provider := 'local', meta := '{"role": "dev-duckdb"}');
CREATE OR REPLACE TABLE _quack_serve AS SELECT now() AS started_at, listen_uri, listen_url
FROM quack_serve(getvariable('quack_uri'), token := getenv('QUACK_TOKEN'));

-- The source rows are rendered into complete programs and sent through the instance's Quack door.
-- Keep each phase in its own statement: later phases depend on the objects created earlier.
CREATE OR REPLACE TEMPORARY TABLE _setup_boot_files AS
SELECT 1 AS phase, 1 AS ordinal, 'server/api_secrets.sql' AS relative_path
UNION ALL SELECT 2, 1, 'server/live.sql'
UNION ALL SELECT 3, 1, 'server/server_instance.sql'
UNION ALL SELECT 4, 1, 'server/quackapi.sql'
UNION ALL SELECT 4, 2, 'server/telemetry.sql'
UNION ALL SELECT 5, 1, 'server/agent_base.sql'
UNION ALL SELECT 5, 2, 'server/agent_stream_tools.sql'
UNION ALL SELECT 5, 3, 'server/duckdb_mcp.sql'
UNION ALL SELECT 6, 1, 'server/observability.sql'
UNION ALL SELECT 6, 2, 'server/query_history.sql'
UNION ALL SELECT 6, 3, 'server/server_diagnostics.sql'
-- CI verifies the boot graph without hydrating optional external catalogs; those crawls remain part
-- of normal development startup and are scheduled separately after the instance is healthy.
UNION ALL SELECT 6, 4, 'server/ext_catalog.sql'
    WHERE nullif(getenv('DUCKSTACK_CI'), '') IS DISTINCT FROM '1'
UNION ALL SELECT 6, 5, 'readthedocs_catalog.sql'
    WHERE nullif(getenv('DUCKSTACK_CI'), '') IS DISTINCT FROM '1'
UNION ALL SELECT 6, 6, 'server/open_prs.sql'
UNION ALL SELECT 6, 7, 'server/luna.sql'
UNION ALL SELECT 6, 8, 'server/agent_stream_schedule.sql'
UNION ALL SELECT 6, 9, 'server/ext_catalog_schedule.sql'
UNION ALL SELECT 6, 10, 'server/cron.sql';

SET VARIABLE setup_boot_secrets = (
    SELECT content FROM read_text(getvariable('server_dir') || '/server/api_secrets.sql')
);
SET VARIABLE setup_boot_context =
    'SET VARIABLE server_dir = ' || chr(39) || replace(getvariable('server_dir'), chr(39), chr(39) || chr(39)) || chr(39) || ';' || chr(10) ||
    'SET VARIABLE quack_uri = ' || chr(39) || replace(getvariable('quack_uri'), chr(39), chr(39) || chr(39)) || chr(39) || ';' || chr(10) ||
    'SET VARIABLE quackapi_port = ' || getvariable('quackapi_port')::VARCHAR || ';' || chr(10) ||
    'SET VARIABLE mcp_port = ' || getvariable('mcp_port')::VARCHAR || ';' || chr(10) ||
    'SET VARIABLE otlp_dir = ' || chr(39) || replace(getvariable('otlp_dir'), chr(39), chr(39) || chr(39)) || chr(39) || ';';

INSTALL quack; LOAD quack; INSTALL httpfs; LOAD httpfs; INSTALL aws; LOAD aws; INSTALL encodings; INSTALL ducklake;
LOAD json; LOAD icu; LOAD parquet; INSTALL fts; LOAD fts; INSTALL postgres; LOAD postgres; INSTALL sqlite; LOAD sqlite;
INSTALL webbed FROM community; LOAD webbed; INSTALL markdown FROM community; LOAD markdown;
INSTALL crawler FROM community; LOAD crawler; INSTALL cronjob FROM community; LOAD cronjob;
INSTALL splink_udfs FROM community; LOAD splink_udfs; INSTALL urlpattern FROM community; LOAD urlpattern;
INSTALL netquack FROM community; LOAD netquack; INSTALL shellfs FROM community; LOAD shellfs;
INSTALL tera FROM community; LOAD tera; INSTALL scalarfs FROM community; LOAD scalarfs;
INSTALL http_client FROM community; LOAD http_client; INSTALL otlp FROM community; LOAD otlp;
INSTALL prometheus FROM community; LOAD prometheus; INSTALL cloudwatch FROM community; LOAD cloudwatch;
INSTALL quack_flamegraph FROM community; LOAD quack_flamegraph; INSTALL observefs FROM community; LOAD observefs;
INSTALL agent_data FROM community; LOAD agent_data; INSTALL duck_tails FROM community; LOAD duck_tails;
INSTALL duck_hunt FROM community; LOAD duck_hunt; INSTALL zipfs FROM community; LOAD zipfs;
INSTALL quickjs FROM community; LOAD quickjs; INSTALL miniplot FROM community; LOAD miniplot;
INSTALL minijinja FROM community; LOAD minijinja; INSTALL gh FROM community; LOAD gh;
INSTALL hostfs FROM community; LOAD hostfs; INSTALL pdf FROM community; LOAD pdf;
INSTALL parser_tools FROM community; LOAD parser_tools; INSTALL yaml FROM community; LOAD yaml;
INSTALL jsonata FROM community; LOAD jsonata; INSTALL sitting_duck FROM community; LOAD sitting_duck; INSTALL curl_httpfs FROM community; LOAD curl_httpfs;

SET VARIABLE setup_boot_program = (
    WITH statements AS (
        SELECT ordinal,
               'SELECT ' || ordinal || ' AS ordinal, content FROM read_text(' ||
               chr(39) || replace(getvariable('server_dir') || '/' || relative_path,
                                    chr(39), chr(39) || chr(39)) || chr(39) || ')' AS statement
        FROM _setup_boot_files
        WHERE phase = 2
    )
    SELECT 'SELECT string_agg(replace(content, chr(36) || ' || chr(39) || 'SERVER_DIR' || chr(39) || ' || chr(36), ' ||
           chr(39) || replace(getvariable('server_dir'), chr(39), chr(39) || chr(39)) || chr(39) ||
           ') || chr(10) || chr(59), chr(10) ORDER BY ordinal) AS program FROM (' ||
           array_to_string(list(statement ORDER BY ordinal), ' UNION ALL ') || ')'
    FROM statements
);
SET VARIABLE setup_boot_program = (
    SELECT getvariable('setup_boot_secrets') || chr(10) || getvariable('setup_boot_context') || chr(10) || program
    FROM query(getvariable('setup_boot_program'))
);
SELECT * FROM quack_query(getvariable('quack_uri'), getvariable('setup_boot_program'), token := getenv('QUACK_TOKEN'));

-- A laptop tenant: leave memory and cores for the desktop; bounded temp; UTC; patient HTTP; fewer checkpoint pauses.
SET GLOBAL memory_limit = '8GB'; SET GLOBAL threads = 10; SET GLOBAL scheduler_process_partial = true;
SET GLOBAL allocator_background_threads = true; SET GLOBAL temp_directory = getenv('HOME') || '/.duck/tmp';
SET GLOBAL max_temp_directory_size = '50GiB'; SET GLOBAL TimeZone = 'UTC'; SET GLOBAL checkpoint_threshold = '128MiB';
SET GLOBAL http_timeout = 120; SET GLOBAL http_retries = 5; SET GLOBAL http_retry_wait_ms = 500;
SET GLOBAL httpfs_connection_caching = true; SET GLOBAL httpfs_client_implementation = 'curl';
SET enable_progress_bar = false; PRAGMA enable_checkpoint_on_shutdown;
-- No query may trigger a silent download; profiling stays settable after the lock; no Hugging Face reads.
SET GLOBAL autoinstall_known_extensions = false; SET GLOBAL allowed_configs = ['enable_profiling', 'profiling_coverage'];
SET GLOBAL disabled_filesystems = 'HuggingFaceFileSystem';

-- Every query on this instance, to one CSV. quackapi_serve switches logging off, so it is applied again after serving.
-- enable_logging(types, level, storage, storage_config, storage_path, storage_normalize, storage_buffer_size)
SET VARIABLE setup_boot_program = (
    WITH statements AS (
        SELECT ordinal,
               'SELECT ' || ordinal || ' AS ordinal, content FROM read_text(' ||
               chr(39) || replace(getvariable('server_dir') || '/' || relative_path,
                                    chr(39), chr(39) || chr(39)) || chr(39) || ')' AS statement
        FROM _setup_boot_files
        WHERE phase = 3
    )
    SELECT 'SELECT string_agg(replace(content, chr(36) || ' || chr(39) || 'SERVER_DIR' || chr(39) || ' || chr(36), ' ||
           chr(39) || replace(getvariable('server_dir'), chr(39), chr(39) || chr(39)) || chr(39) ||
           ') || chr(10) || chr(59), chr(10) ORDER BY ordinal) AS program FROM (' ||
           array_to_string(list(statement ORDER BY ordinal), ' UNION ALL ') || ')'
    FROM statements
);
SET VARIABLE setup_boot_program = (
    SELECT getvariable('setup_boot_context') || chr(10) || program
    FROM query(getvariable('setup_boot_program'))
);
SELECT * FROM quack_query(getvariable('quack_uri'), getvariable('setup_boot_program'), token := getenv('QUACK_TOKEN'));

SET VARIABLE log_path = coalesce(nullif(getenv('QUACK_NATIVE_LOG'), ''), getenv('HOME') || '/.duck/logs/duckdb_log.csv');
CALL enable_logging(['QueryLog', 'HTTP', 'Quack', 'Metrics'], storage := 'file', storage_path := getvariable('log_path'), storage_buffer_size := 0);
CREATE OR REPLACE VIEW query_log AS SELECT * EXCLUDE (type, message), message AS query FROM duckdb_logs WHERE type = 'QueryLog';
CREATE OR REPLACE VIEW http_log AS FROM duckdb_logs_parsed('HTTP');
CREATE OR REPLACE VIEW quack_log AS FROM duckdb_logs_parsed('Quack');
CREATE OR REPLACE VIEW metrics_log AS FROM duckdb_logs_parsed('Metrics');

SET VARIABLE setup_boot_program = (
    WITH statements AS (
        SELECT ordinal,
               'SELECT ' || ordinal || ' AS ordinal, content FROM read_text(' ||
               chr(39) || replace(getvariable('server_dir') || '/' || relative_path,
                                    chr(39), chr(39) || chr(39)) || chr(39) || ')' AS statement
        FROM _setup_boot_files
        WHERE phase = 4 AND ordinal = 1
    )
    SELECT 'SELECT string_agg(replace(replace(content, chr(36) || ' || chr(39) || 'SERVER_DIR' || chr(39) || ' || chr(36), ' ||
           chr(39) || replace(getvariable('server_dir'), chr(39), chr(39) || chr(39)) || chr(39) ||
           '), chr(36) || ' || chr(39) || 'QUACKAPI_PORT' || chr(39) || ' || chr(36), ' ||
           chr(39) || coalesce(nullif(getenv('DEV_QUACKAPI_PORT'), ''), '9495')::VARCHAR || chr(39) ||
           ') || chr(10) || chr(59), chr(10) ORDER BY ordinal) AS program FROM (' ||
           array_to_string(list(statement ORDER BY ordinal), ' UNION ALL ') || ')'
    FROM statements
);
SET VARIABLE setup_boot_program = (
    SELECT getvariable('setup_boot_context') || chr(10) || program
    FROM query(getvariable('setup_boot_program'))
);
SELECT * FROM quack_query(getvariable('quack_uri'), getvariable('setup_boot_program'), token := getenv('QUACK_TOKEN'));

-- The remaining phase-4 source contains raw CREATE ROUTE statements. QuackAPI parses those
-- after its own route is live, so post that small dependent tail through the selected /sql door.
SET VARIABLE setup_boot_program = (
    WITH statements AS (
        SELECT ordinal,
               'SELECT ' || ordinal || ' AS ordinal, content FROM read_text(' ||
               chr(39) || replace(getvariable('server_dir') || '/' || relative_path,
                                    chr(39), chr(39) || chr(39)) || chr(39) || ')' AS statement
        FROM _setup_boot_files
        WHERE phase = 4 AND ordinal > 1
    )
    SELECT 'SELECT string_agg(replace(replace(content, chr(36) || ' || chr(39) || 'SERVER_DIR' || chr(39) || ' || chr(36), ' ||
           chr(39) || replace(getvariable('server_dir'), chr(39), chr(39) || chr(39)) || chr(39) ||
           '), chr(36) || ' || chr(39) || 'QUACKAPI_PORT' || chr(39) || ' || chr(36), ' ||
           chr(39) || coalesce(nullif(getenv('DEV_QUACKAPI_PORT'), ''), '9495')::VARCHAR || chr(39) ||
           ') || chr(10) || chr(59), chr(10) ORDER BY ordinal) AS program FROM (' ||
           array_to_string(list(statement ORDER BY ordinal), ' UNION ALL ') || ')'
    FROM statements
);
SET VARIABLE setup_boot_program = (
    SELECT getvariable('setup_boot_context') || chr(10) || program
    FROM query(getvariable('setup_boot_program'))
);
SELECT CASE WHEN receipt.status = 200 THEN receipt.body ELSE error('setup.sql phase 4 tail failed: ' || receipt.body) END AS body
FROM (SELECT http_post('http://127.0.0.1:' || getvariable('quackapi_port')::VARCHAR || '/sql',
             MAP {'Content-Type': 'application/json'},
             json_object('sql', getvariable('setup_boot_program'))) AS receipt);

CREATE OR REPLACE TABLE _listeners AS SELECT now() AS at, 'quack' AS service, listen_uri AS address FROM quack_server_list()
    UNION ALL SELECT now(), 'quackapi', listen_url FROM quackapi_servers()
    UNION ALL SELECT now(), 'mcp', 'http://localhost:' || getvariable('mcp_port') || '/mcp';
INSERT OR REPLACE INTO meta.runtime_endpoints (service, address, recorded_at)
SELECT service, address, "at" FROM _listeners;

INSTALL duckdb_mcp FROM community; LOAD duckdb_mcp;
SET VARIABLE setup_boot_program = (
    WITH statements AS (
        SELECT ordinal,
               'SELECT ' || ordinal || ' AS ordinal, content FROM read_text(' ||
               chr(39) || replace(getvariable('server_dir') || '/' || relative_path,
                                    chr(39), chr(39) || chr(39)) || chr(39) || ')' AS statement
        FROM _setup_boot_files
        WHERE phase = 5
    )
    SELECT 'SELECT string_agg(replace(content, chr(36) || ' || chr(39) || 'SERVER_DIR' || chr(39) || ' || chr(36), ' ||
           chr(39) || replace(getvariable('server_dir'), chr(39), chr(39) || chr(39)) || chr(39) ||
           ') || chr(10) || chr(59), chr(10) ORDER BY ordinal) AS program FROM (' ||
           array_to_string(list(statement ORDER BY ordinal), ' UNION ALL ') || ')'
    FROM statements
);
SET VARIABLE setup_boot_program = (
    SELECT getvariable('setup_boot_context') || chr(10) || program
    FROM query(getvariable('setup_boot_program'))
);
SELECT * FROM quack_query(getvariable('quack_uri'), getvariable('setup_boot_program'), token := getenv('QUACK_TOKEN'));

CALL enable_logging(['QueryLog', 'HTTP', 'Quack', 'Metrics'], storage := 'file', storage_path := getvariable('log_path'), storage_buffer_size := 0);

SET VARIABLE setup_boot_program = (
    WITH statements AS (
        SELECT ordinal,
               'SELECT ' || ordinal || ' AS ordinal, content FROM read_text(' ||
               chr(39) || replace(getvariable('server_dir') || '/' || relative_path,
                                    chr(39), chr(39) || chr(39)) || chr(39) || ')' AS statement
        FROM _setup_boot_files
        WHERE phase = 6 AND ordinal = 1
    )
    SELECT 'SELECT string_agg(replace(content, chr(36) || ' || chr(39) || 'SERVER_DIR' || chr(39) || ' || chr(36), ' ||
           chr(39) || replace(getvariable('server_dir'), chr(39), chr(39) || chr(39)) || chr(39) ||
           ') || chr(10) || chr(59), chr(10) ORDER BY ordinal) AS program FROM (' ||
           array_to_string(list(statement ORDER BY ordinal), ' UNION ALL ') || ')'
    FROM statements
);
SET VARIABLE setup_boot_program = (
    SELECT getvariable('setup_boot_context') || chr(10) || program
    FROM query(getvariable('setup_boot_program'))
);
-- Observability declares a raw CREATE ROUTE. Let the live QuackAPI parser handle it, as for the
-- phase-4 route tail, before dispatching the remaining phase-6 SQL through native Quack.
SELECT CASE WHEN receipt.status = 200 THEN receipt.body ELSE error('setup.sql phase 6 route failed: ' || receipt.body) END AS body
FROM (SELECT http_post('http://127.0.0.1:' || getvariable('quackapi_port')::VARCHAR || '/sql',
             MAP {'Content-Type': 'application/json'},
             json_object('sql', getvariable('setup_boot_program'))) AS receipt);

SET VARIABLE setup_boot_program = (
    WITH statements AS (
        SELECT ordinal,
               'SELECT ' || ordinal || ' AS ordinal, content FROM read_text(' ||
               chr(39) || replace(getvariable('server_dir') || '/' || relative_path,
                                    chr(39), chr(39) || chr(39)) || chr(39) || ')' AS statement
        FROM _setup_boot_files
        WHERE phase = 6 AND ordinal > 1
    )
    SELECT 'SELECT string_agg(replace(content, chr(36) || ' || chr(39) || 'SERVER_DIR' || chr(39) || ' || chr(36), ' ||
           chr(39) || replace(getvariable('server_dir'), chr(39), chr(39) || chr(39)) || chr(39) ||
           ') || chr(10) || chr(59), chr(10) ORDER BY ordinal) AS program FROM (' ||
           array_to_string(list(statement ORDER BY ordinal), ' UNION ALL ') || ')'
    FROM statements
);
SET VARIABLE setup_boot_program = (
    SELECT getvariable('setup_boot_context') || chr(10) || program
    FROM query(getvariable('setup_boot_program'))
);
SELECT * FROM quack_query(getvariable('quack_uri'), getvariable('setup_boot_program'), token := getenv('QUACK_TOKEN'));

-- Subagents (Lunas, spawned agents) read anything here but write only into agent_scratch; every other
-- schema is changed by direct sessions. Convention, not enforcement: DuckDB has no per-user grants.
CREATE SCHEMA IF NOT EXISTS agent_scratch;

-- The effective configuration, every start; then refuse to serve a crippled or over-permissive instance.
CREATE OR REPLACE TABLE _setup_settings AS SELECT now() AS recorded_at, * FROM duckdb_settings();
CREATE TABLE IF NOT EXISTS _setup_settings_history AS FROM _setup_settings LIMIT 0;
INSERT INTO _setup_settings_history BY NAME FROM _setup_settings;
SELECT error('setup.sql: refusing to serve -- ' || name || ' = ' || value) FROM duckdb_settings()
WHERE name || '=' || value IN ('allow_community_extensions=false', 'enable_external_access=false',
    'allow_unsigned_extensions=true', 'allow_unredacted_secrets=true');
CREATE OR REPLACE TABLE _setup_complete AS SELECT now() AS completed_at;
-- After this no connection can SET/PRAGMA/RESET; INSTALL, LOAD, ATTACH and HTTP still work.
SET GLOBAL lock_configuration = true;
