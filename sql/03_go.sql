/* pgtab: go()
 * Schemas, views, procedures for viewing/editing package data with psql.
 */

-- install go procedures in main schema
SET search_path TO pgtab;


CREATE PROCEDURE go_(
  package                   TEXT = NULL        ,
  resource                  TEXT = NULL        ,
  field                     TEXT = NULL        ,
  selected       INOUT      TEXT = ''          )
LANGUAGE plpgsql
  SECURITY DEFINER SET search_path = pgtab
  AS $PROC$
BEGIN
  IF package IS NULL THEN -- go to pgtab
    resource := null;
    field := null;
    SET search_path TO pgtab;
    selected := NULL::text;
  ELSE
    PERFORM * FROM package WHERE name=go_.package; -- go to pgtab_p
    IF NOT FOUND THEN
      RAISE EXCEPTION '[pgtab] not found: package.name=''%''', package;
    END IF;
    SET search_path TO pgtab_p;
    selected := FORMAT('package: %s', package);
    IF resource IS NOT NULL THEN -- go to pgtab_r
      PERFORM *
         FROM pgtab.resource r
        WHERE r.package=go_.package
          AND r.name=go_.resource;
      IF NOT FOUND THEN
        RAISE EXCEPTION '[pgtab] not found: package=''%'', resource=''%''',
          package, resource;
      END IF;
      SET search_path TO pgtab_r;
      selected := FORMAT('package: %s, resource: %s', package, resource);
    END IF;
    IF field IS NOT NULL THEN -- go to pgtab_f
      PERFORM *
         FROM pgtab.field f
        WHERE f.package=go_.package
          AND f.resource=go_.resource
          AND f.name=go_.field;
      IF NOT FOUND THEN
        RAISE EXCEPTION
          '[pgtab] not found: package=''%'', resource=''%'', field=''%''',
          package, resource, field;
      END IF;
      SET search_path TO pgtab_f;
      selected := FORMAT('package: %s, resource: %s, field: %s',
                         package, resource, field);
    END IF;
  END IF;
  PERFORM set_config('pgtab_go.package', package, FALSE);
  PERFORM set_config('pgtab_go.resource', resource, FALSE);
  PERFORM set_config('pgtab_go.field', field, FALSE);
END;
$PROC$;
COMMENT ON PROCEDURE go_ IS
  'set session variables to view selected package object';


CREATE PROCEDURE go(search_term TEXT = NULL, selected INOUT TEXT = '')
  LANGUAGE plpgsql AS $PROC$
DECLARE
  rec RECORD;
BEGIN
  IF COALESCE(search_term, '') = '' THEN
    CALL pgtab.go_(selected=>selected);
  ELSE
    search_term := search_term || '%';
    SELECT name, count(*) OVER () AS n
      INTO rec
      FROM pgtab.p WHERE name ~~* search_term
      LIMIT 1;
    CASE
      WHEN NOT FOUND THEN RAISE EXCEPTION
        'package.name ~~* ''%'' NOT FOUND', search_term;
      WHEN rec.n > 1 THEN RAISE EXCEPTION
        'package.name ~~* ''%'' returns more than one row', search_term;
      ELSE
    END CASE;
    CALL go_(rec.name, selected=>selected);
  END IF;
END;
$PROC$;
COMMENT ON PROCEDURE go IS 'go to selected package object';


/*
 * SCHEMA pgtab_p: selected package
 */
DROP SCHEMA IF EXISTS pgtab_p CASCADE;
CREATE SCHEMA pgtab_p;
COMMENT ON SCHEMA pgtab_p IS 'pgtab: selected package';

SET search_path TO pgtab_p;

/* VIEWS */
CREATE VIEW p AS
 SELECT name,
        title,
        id,
        hash,
        bytes,
        version,
        created,
        last_updated
   FROM pgtab.package
  WHERE name = current_setting('pgtab_go.package', TRUE);
COMMENT ON VIEW p IS 'selected package';


CREATE VIEW custom AS
 SELECT jsonb_pretty(custom) AS custom
   FROM pgtab.package
  WHERE name = current_setting('pgtab_go.package', TRUE);
COMMENT ON VIEW custom IS 'package custom JSON elements';


CREATE VIEW readme AS
 SELECT readme
   FROM pgtab.package
  WHERE name = current_setting('pgtab_go.package', TRUE);
COMMENT ON VIEW readme IS 'package readme';


CREATE VIEW description AS
 SELECT description
   FROM pgtab.package
  WHERE name = current_setting('pgtab_go.package', TRUE);
COMMENT ON VIEW description IS 'package description';


CREATE VIEW r AS
    SELECT name,
           title,
           format,
           (SELECT count(*)
              FROM pgtab.field
             WHERE field.package = resource.package
               AND field.resource = resource.name) AS fields
      FROM pgtab.resource
     WHERE package = current_setting('pgtab_go.package', TRUE)
  ORDER BY 1;
COMMENT ON VIEW r IS 'package resources';


/* PROCEDURES */
CREATE PROCEDURE go(search_term TEXT = NULL, selected INOUT TEXT = '')
  LANGUAGE plpgsql AS $PROC$
DECLARE
  _package TEXT := current_setting('pgtab_go.package', TRUE);
  rec RECORD;
BEGIN
  IF COALESCE(search_term, '') = '' THEN
    CALL pgtab.go_(selected=>selected);
  ELSE
    SELECT name, count(*) OVER () AS n
      INTO rec
      FROM pgtab.resource
     WHERE package = _package
       AND name ~~* search_term
      LIMIT 1;
    CASE
      WHEN NOT FOUND THEN RAISE EXCEPTION
        'resource.name ~~* ''%'' NOT FOUND', search_term;
      WHEN rec.n > 1 THEN RAISE EXCEPTION
        'resource.name ~~* ''%'' returns more than one row', search_term;
      ELSE
    END CASE;
    CALL pgtab.go_(_package, rec.name, selected=>selected);
  END IF;
END;
$PROC$;
COMMENT ON PROCEDURE go IS 'select resource';

/*
 * SCHEMA pgtab_r: selected resource
 */
DROP SCHEMA IF EXISTS pgtab_r CASCADE;
CREATE SCHEMA pgtab_r;
COMMENT ON SCHEMA pgtab_r IS 'pgtab: selected resource';

SET search_path TO pgtab_r;

/* VIEWS */
CREATE VIEW p AS SELECT * FROM pgtab_p.p;
COMMENT ON VIEW p IS 'selected package';

CREATE VIEW r AS
 SELECT name,
        title,
        description,
        format,
        encoding,
        path,
        last_updated,
        jsonb_pretty(csv_dialect) AS csv_dialect,
        jsonb_pretty(schema_custom) AS schema_custom
   FROM pgtab.resource
  WHERE package = current_setting('pgtab_go.package', TRUE)
    AND name = current_setting('pgtab_go.resource', TRUE);
COMMENT ON VIEW r IS 'selected resource';


CREATE VIEW custom AS
 SELECT jsonb_pretty(custom) AS custom
   FROM pgtab.resource
  WHERE name = current_setting('pgtab_go.package', TRUE)
    AND name = current_setting('pgtab_go.resource', TRUE);
COMMENT ON VIEW custom IS 'resource custom JSON elements';


CREATE VIEW f AS
    SELECT ordinal_position AS "#",
           name,
           type,
           title,
           description,
           format
      FROM pgtab.field
     WHERE package = current_setting('pgtab_go.package', TRUE)
       AND resource = current_setting('pgtab_go.resource', TRUE)
  ORDER BY 1;
COMMENT ON VIEW f IS 'selected resource fields';


/* PROCEDURES */
CREATE PROCEDURE go(ord_pos INT, selected INOUT TEXT = '')
  LANGUAGE plpgsql AS $PROC$
DECLARE
  _package TEXT := current_setting('pgtab_go.package', TRUE);
  _resource TEXT := current_setting('pgtab_go.resource', TRUE);
  _name TEXT;
BEGIN
  IF NULLIF(ord_pos, 0) IS NULL THEN
    _name := NULL;
  ELSE
    SELECT name
      INTO _name
      FROM pgtab.field
     WHERE package = _package AND resource = _resource
       AND ordinal_position = ord_pos;
   END IF;
  CALL pgtab.go_(_package, _resource, _name, selected=>selected);
END;
$PROC$;
COMMENT ON PROCEDURE go(INT, TEXT) IS 'select field by #';


CREATE PROCEDURE go(package TEXT = NULL, selected INOUT TEXT = '')
  LANGUAGE plpgsql AS $PROC$
BEGIN
  IF package = '' THEN
    package := current_setting('pgtab_go.package',TRUE);
  END IF;
  CALL pgtab.go_(package, selected=>selected);
END;
$PROC$;
COMMENT ON PROCEDURE go(TEXT, TEXT) IS 'select parent package';


/*
 * SCHEMA pgtab_f: selected field
 */
DROP SCHEMA IF EXISTS pgtab_f CASCADE;
CREATE SCHEMA pgtab_f;
COMMENT ON SCHEMA pgtab_f IS 'pgtab: selected field';

SET search_path TO pgtab_f;

/* VIEWS */
CREATE VIEW p AS SELECT * FROM pgtab_p.p;
COMMENT ON VIEW p IS 'selected package';


CREATE VIEW r AS SELECT * FROM pgtab_r.r;
COMMENT ON VIEW r IS 'selected resource';


CREATE VIEW f AS
  SELECT ordinal_position AS "#",
         name,
         type,
         title,
         description,
         format,
         jsonb_pretty(custom) AS custom
    FROM pgtab.field
   WHERE package = current_setting('pgtab_go.package', TRUE)
     AND resource = current_setting('pgtab_go.resource', TRUE)
     AND name = current_setting('pgtab_go.field', TRUE);
COMMENT ON VIEW f IS 'selected field';


/* PROCEDURES */
CREATE PROCEDURE go(ord_pos INT = NULL, selected INOUT TEXT = '')
  LANGUAGE plpgsql AS $PROC$
BEGIN
  IF ord_pos IS NULL THEN
    CALL pgtab.go_(NULL::TEXT, selected=>selected);
  ELSE
    CALL pgtab_r.go(ord_pos, selected);
  END IF;
END;
$PROC$;
COMMENT ON PROCEDURE go(INT, TEXT) IS 'select field by #';


CREATE PROCEDURE go(package TEXT, selected INOUT TEXT = '')
  LANGUAGE plpgsql AS $PROC$
BEGIN
  CALL pgtab.go_(current_setting('pgtab_go.package', TRUE),
    current_setting('pgtab_go.resource', TRUE), selected=>selected);
END;
$PROC$;
COMMENT ON PROCEDURE go(TEXT, TEXT) IS 'select parent package';
