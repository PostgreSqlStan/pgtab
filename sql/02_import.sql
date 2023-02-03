/* SCHEMA: pgtab_i (import)
 * load and map JSON to table columns
 */

DROP SCHEMA IF EXISTS pgtab_i CASCADE;
CREATE SCHEMA pgtab_i;
COMMENT ON SCHEMA pgtab_i IS 'pgtab: import json';

SET search_path TO pgtab_i;

/* TABLES (and TRIGGERS) */
CREATE UNLOGGED TABLE i_text(t TEXT);
COMMENT ON TABLE i_text IS 'json as csv source';

CREATE UNLOGGED TABLE i_json(j jsonb);
COMMENT ON TABLE i_json IS 'json source';


CREATE FUNCTION tf_fix_multiline_json()
  RETURNS TRIGGER AS $TF$
  -- ⚠️ probably bad idea, but had to try it
  -- will likely remove (soon) and perform in procedure instead
  -- conditionally remove linefeeds from multiline json
DECLARE
  is_json_rows BOOL;
BEGIN
  IF ((SELECT COUNT(*) FROM i_text LIMIT 2) > 1) THEN
    WITH a AS (SELECT distinct(left(t,1) || right(t,1)) AS da
                 FROM i_text LIMIT 5)
      SELECT (SELECT count(*) FROM a)=1 AND (SELECT TRUE FROM a WHERE da='{}')
        INTO is_json_rows;
    -- don't concatenate to single row if it's rows of valid JSON
    IF NOT is_json_rows THEN
      CREATE TEMPORARY TABLE fix(t TEXT);
      INSERT INTO fix SELECT string_agg(t, ' ') FROM i_text;
      DELETE FROM i_text;
      INSERT INTO i_text SELECT * FROM fix;
      DROP TABLE fix;
    END IF;
  END IF;
  RETURN NEW;
END;
$TF$ LANGUAGE plpgsql;


CREATE TRIGGER fix_multiline_json AFTER INSERT ON i_text
  EXECUTE FUNCTION tf_fix_multiline_json();


/* VIEWS
 * map imported JSON object contents to tables (package, resource, field)
 * "schema:" non-field keys are mapped to resource.schema_custom
 * other keys (w/o corresponding columns) mapped to custom
 */

CREATE VIEW i AS
  SELECT CASE
           WHEN (SELECT count(*) FROM i_json LIMIT 1) > 0 THEN
             (SELECT j FROM i_json)
           WHEN (SELECT count(*) FROM i_text LIMIT 1) > 0 THEN
             (SELECT t::jsonb AS j FROM i_text)
         END AS j;
COMMENT ON VIEW i IS 'import source';


CREATE VIEW pj AS
  SELECT
    j->>'name' AS name,
    j->'resources' as j_resources,
    j - 'name' - 'resources' - 'title' - 'description' - 'profile' - 'id'
      - 'hash' - 'bytes' - 'version' - 'readme' - 'created' - 'last_udpated'
      AS custom
  FROM i;
COMMENT ON VIEW pj IS 'package JSON elements';


CREATE VIEW rj AS
  SELECT
    name as package,
    CASE WHEN jr ? 'name' THEN jr->>'name' ELSE 'unknown' END AS name,
    jr->'schema'->'fields' AS j_fields,
    jr - 'name' - 'schema' - 'title' - 'description' - 'profile'
     - 'hash' - 'bytes' - 'format' - 'encoding' - 'path' - 'dialect'
     AS custom,
     (jr->'schema') - 'fields' AS schema_custom
  FROM pj,
    LATERAL jsonb_array_elements(j_resources) AS jr;
COMMENT ON VIEW rj IS 'resource JSON elements';


CREATE VIEW p AS
  SELECT
    j->>'name' AS name,
    CASE WHEN j ? 'title' THEN j->>'title' ELSE NULL END AS title,
    CASE WHEN j ? 'description' THEN j->>'description' ELSE NULL END
      AS description,
    CASE WHEN j ? 'profile' THEN j->>'profile' ELSE NULL END AS profile,
    CASE WHEN j ? 'id' THEN j->>'id' ELSE NULL END AS id,
    CASE WHEN j ? 'hash' THEN j->>'hash' ELSE NULL END AS hash,
    CASE WHEN j ? 'bytes' THEN j->>'bytes' ELSE NULL END AS bytes,
    CASE WHEN j ? 'version' THEN j->>'version' ELSE NULL END AS version,
    CASE WHEN j ? 'readme' THEN j->>'readme' ELSE NULL END AS readme,
    CASE WHEN j ? 'created' THEN (j->>'created')::timestamptz ELSE NULL END
     AS created,
    CASE WHEN j ? 'last_updated' THEN (j->>'last_updated')::timestamptz
      ELSE NULL END AS last_updated,
    CASE WHEN custom = '{}'::jsonb THEN NULL ELSE custom END AS custom
  FROM i
    JOIN pj ON (i.j->>'name' = pj.name);
COMMENT ON VIEW p IS 'imported JSON -> package columns';


CREATE VIEW r AS
  SELECT
    pj.name AS package,
    -- set resource.name to 'unknown' when NULL:
    CASE WHEN jr ? 'name' THEN jr->>'name' ELSE 'unknown' END AS name,
    CASE WHEN jr ? 'title' THEN jr->>'title' ELSE NULL END AS title,
    CASE WHEN jr ? 'description' THEN jr->>'description' ELSE NULL END
      AS description,
    CASE WHEN jr ? 'profile' THEN jr->>'profile' ELSE NULL END AS profile,
    CASE WHEN jr ? 'hash' THEN jr->>'hash' ELSE NULL END AS hash,
    CASE WHEN jr ? 'bytes' THEN jr->>'bytes' ELSE NULL END AS bytes,
    CASE WHEN jr ? 'format' THEN jr->>'format' ELSE NULL END AS format,
    CASE WHEN jr ? 'encoding' THEN jr->>'endoding' ELSE NULL END AS encoding,
    CASE WHEN jr ? 'path' THEN jr->>'path' ELSE NULL END AS path,
    CASE WHEN jr ? 'dialect' THEN jr->'dialect' ELSE NULL END AS csv_dialect,
    CASE WHEN jr ? 'last_updated'
      THEN (jr->>'last_updated')::timestamptz ELSE NULL END AS last_updated,
    CASE WHEN rj.custom = '{}'::jsonb THEN NULL ELSE rj.custom END AS custom,
    CASE WHEN rj.schema_custom = '{}'::jsonb
           THEN NULL ELSE rj.schema_custom END
      AS schema_custom
  FROM pj,
    LATERAL jsonb_array_elements(j_resources) AS jr
    JOIN rj ON (package = rj.package
                AND COALESCE(jr->>'name', 'unknown') = rj.name);
COMMENT ON VIEW r IS 'imported JSON -> resource columns';


CREATE VIEW f AS
  SELECT
    package,
    name as resource,
    jf->>'name' as name,
    jf->>'type' as type,
    CASE WHEN jf ? 'title' THEN jf->>'title' ELSE NULL END AS title,
    CASE WHEN jf ? 'description' THEN jf->>'description' ELSE NULL END
      AS description,
    CASE WHEN jf ? 'format' THEN jf->>'format' ELSE NULL END AS format,
    CASE WHEN
      (jf - 'name' - 'type' - 'description' - 'format' = '{}'::jsonb) THEN
      NULL ELSE jf->'custom' END AS custom
  FROM rj,
    LATERAL jsonb_array_elements(j_fields) AS jf;
COMMENT ON VIEW f IS 'imported JSON -> field columns';


CREATE VIEW i_resources AS
   SELECT package,
          name AS resource,
          (SELECT count(*) FROM f WHERE f.resource = r.name) AS fields
     FROM r;
COMMENT ON VIEW i_resources IS 'view: imported package resources';


CREATE VIEW import_methods AS
  SELECT 'csv' as method,
  $$\COPY i_text FROM datapackage.json csv quote e'\x01' delimiter e'\x02'$$
    AS example
  UNION
  SELECT 'variable',
  $$\set obj `cat datapackage.json`
INSERT INTO i_json SELECT :'obj';
\set obj$$
  UNION
  SELECT '\lo_import',
$$BEGIN;
\set filename datapackage.json
\lo_import :filename
\set obj :LASTOID
INSERT INTO i_text
  SELECT *
    FROM convert_from(lo_get(:'obj'),'UTF8');
\lo_unlink :obj
COMMIT;$$;
COMMENT ON VIEW import_methods IS 'view: JSON import examples'
