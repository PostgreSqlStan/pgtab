/* UNFINISHED STUFF */

SET search_path TO pgtab;

CREATE FUNCTION pgtab_version() RETURNS TEXT LANGUAGE SQL
  RETURN '0.1 (alpha)';
COMMENT ON FUNCTION pgtab_version IS 'return pgtab version';


/* schema: pgtab_i
 * json -> database insert procedures
 */
SET search_path TO pgtab_i;

CREATE FUNCTION i_to_package()
  RETURNS SETOF TEXT
  LANGUAGE SQL
BEGIN ATOMIC
  INSERT INTO pgtab.package SELECT * FROM p
    ON CONFLICT DO NOTHING
    RETURNING name;
END;


CREATE FUNCTION i_to_resource()
  RETURNS TABLE (package TEXT, resource TEXT)
  LANGUAGE SQL
BEGIN ATOMIC
  INSERT INTO pgtab.resource SELECT * FROM r
    ON CONFLICT DO NOTHING
    RETURNING package, name;
END;


CREATE FUNCTION i_to_field()
  RETURNS TABLE  (package TEXT, resource TEXT, name TEXT)
  LANGUAGE SQL
BEGIN ATOMIC
  INSERT INTO pgtab.field SELECT * FROM f
    ON CONFLICT DO NOTHING
    RETURNING package, resource, name;
END;


CREATE OR REPLACE PROCEDURE insert_imported () LANGUAGE plpgsql AS $PROC$
/* call pgtab_i procedures to insert data extracted from import_json
 * bravely ignoring any conflicts
 * first draft skeleton procedure with lots of room for improvement
 */
BEGIN
  PERFORM i_to_package();
  PERFORM i_to_resource();
  PERFORM i_to_field();
  TRUNCATE i_text;
  TRUNCATE i_json;
END;
$PROC$;


/* schema: pgtab_i
 * import fields
 */
SET search_path TO pgtab_i;

CREATE UNLOGGED TABLE i_fields(
  package       TEXT,
  resource      TEXT,
  name          TEXT,
  type          TEXT,
  title         TEXT,
  description   TEXT,
  format        TEXT);
COMMENT ON TABLE i_fields IS '(new) import fields table'
