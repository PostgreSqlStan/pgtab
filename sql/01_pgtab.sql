/* SCHEMA pgtab (main) */

DROP SCHEMA IF EXISTS pgtab CASCADE;
CREATE SCHEMA pgtab;
COMMENT ON SCHEMA pgtab IS 'pgtab: main';

SET search_path TO pgtab;

/* TABLES (and TRIGGERS) */
CREATE TABLE package(
  name                    TEXT                                  ,
  title                   TEXT                                  ,
  description             TEXT                                  ,
  profile                 TEXT                                  ,
  id                      TEXT                                  ,
  hash                    TEXT                                  ,
  bytes                   TEXT                                  ,
  version                 TEXT                                  ,
  readme                  TEXT                                  ,
  created                 TIMESTAMPTZ    DEFAULT now()          ,
  last_updated            TIMESTAMPTZ    DEFAULT now()          ,
  custom                  JSONB                                 ,
  PRIMARY KEY (name)                                            );
COMMENT ON TABLE package IS 'packages';


CREATE TABLE resource(
  package                 TEXT                                  ,
  name                    TEXT                                  ,
  title                   TEXT                                  ,
  description             TEXT                                  ,
  profile                 TEXT                                  ,
  hash                    TEXT                                  ,
  bytes                   TEXT                                  ,
  format                  TEXT           DEFAULT 'csv'          ,
  encoding                TEXT           DEFAULT 'utf-8'        ,
  path                    TEXT                                  ,
  csv_dialect             JSONB                                 ,
  last_updated            TIMESTAMPTZ    DEFAULT now()          ,
  custom                  JSONB                                 ,
  schema_custom           JSONB                                 ,
  PRIMARY KEY (package, name)                                   ,
  FOREIGN KEY (package) REFERENCES package(name)
    ON DELETE CASCADE ON UPDATE CASCADE                         );
COMMENT ON TABLE resource IS 'package resources';


CREATE OR REPLACE FUNCTION tf_resource_updated()
  -- set last_updated; called when resource or any related field modified
  RETURNS trigger
  SECURITY DEFINER SET search_path = pgtab
  LANGUAGE plpgsql
  AS $FUNC$
BEGIN
  CASE TG_TABLE_NAME
    WHEN 'resource' THEN NEW.last_updated = now();
    WHEN 'field' THEN
      IF (TG_OP = 'DELETE') THEN
        UPDATE resource r
           SET last_updated = now()
         WHERE r.package = OLD.package AND r.name = OLD.resource;
        RETURN OLD;
      ELSE
        UPDATE resource r
           SET last_updated = now()
         WHERE r.package = NEW.package AND r.name = NEW.resource;
      END IF;
    END CASE;
  RETURN NEW;
END;
$FUNC$;
COMMENT ON FUNCTION tf_resource_updated IS
  'trigger function: set resource.last_updated';


CREATE TRIGGER resource_updated BEFORE INSERT OR UPDATE ON resource
  FOR EACH ROW EXECUTE PROCEDURE tf_resource_updated();


CREATE TABLE field(
  package           TEXT                                        ,
  resource          TEXT                                        ,
  name              TEXT                                        ,
  type              TEXT DEFAULT 'string'                       ,
  title             TEXT                                        ,
  description       TEXT                                        ,
  format            TEXT                                        ,
  custom            JSONB                                       ,
  last_updated      TIMESTAMPTZ  DEFAULT now()                  ,
  ordinal_position  INT                                         ,
  PRIMARY KEY (package, resource, name)                         ,
  FOREIGN KEY (package,resource)
    REFERENCES resource(package, name)
    ON DELETE CASCADE ON UPDATE CASCADE                         );
COMMENT ON TABLE field IS 'resource fields';


CREATE OR REPLACE FUNCTION tf_field_pos()
  -- autoset field ordinal_position;
  RETURNS TRIGGER
  SECURITY DEFINER SET search_path = pgtab
  LANGUAGE plpgsql
  AS $FUNC$
BEGIN
  SELECT count(*) + 1
    INTO NEW.ordinal_position
    FROM field
   WHERE package = NEW.package AND resource = NEW.resource;
  RETURN NEW;
END;
$FUNC$;
COMMENT ON FUNCTION tf_field_pos IS
  'trigger function: set field.ordinal_position';


CREATE TRIGGER field_updated BEFORE INSERT OR UPDATE OR DELETE ON field
  FOR EACH ROW EXECUTE PROCEDURE tf_resource_updated();

CREATE TRIGGER infield_fnum BEFORE INSERT ON field
  FOR EACH ROW EXECUTE PROCEDURE tf_field_pos();


/* VIEWS */
CREATE VIEW p AS
    SELECT name,
           version,
           title
      FROM package
  GROUP BY name
  ORDER BY last_updated DESC;
COMMENT ON VIEW p IS 'view: package';


CREATE VIEW jf AS
    SELECT package,
           resource,
           jsonb_build_object('name', name, 'type', type) AS j_field
      FROM pgtab.field
  ORDER BY 1, 2, ordinal_position;
COMMENT ON VIEW jf IS 'view: JSONB fields';


CREATE VIEW jr AS
    SELECT package,
           resource,
           jsonb_build_object(
             'name', resource,
             'profile', 'tabular-data-resource',
             'schema', jsonb_build_object('fields', jsonb_agg(j_field))
             ) AS j_resource
      FROM jf
  GROUP BY 1, 2;
COMMENT ON VIEW jr IS 'view: JSONB resources';


CREATE VIEW jp AS
    SELECT package,
           jsonb_build_object(
             'name', package,
             'pgtab_version', pgtab.pgtab_version(),
             'profile', 'tabular-data-package',
             'resources', jsonb_agg(j_resource)
             ) AS j_package
      FROM jr
  GROUP BY 1;
COMMENT ON VIEW jp IS 'view: JSONB package';


CREATE VIEW _ls AS
  -- functions (and procedures)
  SELECT n.nspname as "Schema",
   CASE p.prokind
    WHEN 'p' THEN 'proc'
    ELSE 'func'
   END as "Type",
    p.proname as "Name",
   pg_catalog.obj_description(p.oid, 'pg_proc') as "Description"
  FROM pg_catalog.pg_proc p
       LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE pg_catalog.pg_function_is_visible(p.oid)
        AND n.nspname <> 'pg_catalog'
        AND n.nspname <> 'information_schema'
  UNION ALL
  -- relations
  SELECT n.nspname as "Schema",
    CASE c.relkind
      WHEN 'r' THEN 'table'
      WHEN 'v' THEN 'view'
      WHEN 'm' THEN 'materialized view'
      WHEN 'i' THEN 'index'
      WHEN 'S' THEN 'sequence'
      WHEN 's' THEN 'special'
      WHEN 't' THEN 'TOAST table'
      WHEN 'f' THEN 'foreign table'
      WHEN 'p' THEN 'partitioned table'
      WHEN 'I' THEN 'partitioned index' END as "Type",
    c.relname as "Name",
    pg_catalog.obj_description(c.oid, 'pg_class') as "Description"
  FROM pg_catalog.pg_class c
       LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
       LEFT JOIN pg_catalog.pg_am am ON am.oid = c.relam
  WHERE c.relkind IN ('r','p','v','m','S','f','')
        AND n.nspname <> 'pg_catalog'
        AND n.nspname !~ '^pg_toast'
        AND n.nspname <> 'information_schema'
    AND pg_catalog.pg_table_is_visible(c.oid)
  ORDER BY 1, 2, 3 ;
COMMENT ON VIEW _ls IS 'view: schema db objects';

