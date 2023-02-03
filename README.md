# pgtab

`pgtab` is a sample PostgreSQL database which can import, parse, construct, and export JSON [Tabular Data Packages](https://specs.frictionlessdata.io/tabular-data-package/).

This is a learning project, not intended to do anything that can't be accomplished with existing external tools.

![pgtab installation screenshot](https://github.com/postgresqlstan/pgtab/blob/assets/pgtab_install_screenshot.jpg)


Feedback is welcome. Create a repo [issue](https://github.com/PostgreSqlStan/pgtab/issues/new), a [discussion](https://github.com/PostgreSqlStan/pgtab/discussions), or tag me on [twitter](https://twitter.com/PostgreSQLStan).

Contributions *might* be welcome.

### :warning: Use at your own risk.

*This is a work in progress and subject to change. Don't assume anything here works correctly or represents best practices. Some of my [experiments](https://github.com/PostgreSqlStan/pgtab/issues/2) are probably misguided.*

## Installation

**Requirements:** PostgreSQL 14 or newer.

Clone this repo and launch psql from the `pgtab` directory:

```
git clone git@github.com:PostgreSqlStan/pgtab.git
cd pgtab
psql -U postgres
```

:exclamation: You don't know me and have no reason to trust me. So, follow the [Principle of Least Privilege](https://en.wikipedia.org/wiki/Principle_of_least_privilege) and use `pgtab` with a normal (not superuser) account.

Create the database, connect to it with an appropriate account, and run the `build.psql` script:

```
create database pgtab owner stan;
\c pgtab stan
\i build.psql
```

Optionally, run `load_packages.psql` to import sample data packages from the `packages` directory:

```
\i load_packages.psql
```

## Contents

`pgtab` is organized into multiple postgres schemas (namespaces):

```
pgtab=> \dn+
                           List of schemas
  Name   │  Owner   │  Access privileges   │       Description
─────────┼──────────┼──────────────────────┼──────────────────────────
 pgtab   │ stan     │                      │ pgtab: main
 pgtab_f │ stan     │                      │ pgtab: selected field
 pgtab_i │ stan     │                      │ pgtab: import json
 pgtab_p │ stan     │                      │ pgtab: selected package
 pgtab_r │ stan     │                      │ pgtab: selected resource
```

The utility view `pgtab._ls` lists visible `pgtab` objects and their descriptions.

```
pgtab=> table _ls;
 Schema │ Type  │        Name         │                      Description
────────┼───────┼─────────────────────┼───────────────────────────────────────────────────────
 pgtab  │ func  │ pgtab_version       │ return pgtab version
 pgtab  │ func  │ tf_field_pos        │ trigger function: set field.ordinal_position
 pgtab  │ func  │ tf_resource_updated │ trigger function: set resource.last_updated
 pgtab  │ proc  │ go                  │ go to selected package object
 pgtab  │ proc  │ go_                 │ set session variables to view selected package object
 pgtab  │ table │ field               │ resource fields
 pgtab  │ table │ package             │ packages
 pgtab  │ table │ resource            │ package resources
 pgtab  │ view  │ _ls                 │ view: schema objects
 pgtab  │ view  │ jf                  │ view: JSONB fields
 pgtab  │ view  │ jp                  │ view: JSONB package
 pgtab  │ view  │ jr                  │ view: JSONB resources
 pgtab  │ view  │ p                   │ view: package
```

## `go()` – a psql UI

The `go` procedure makes it easy to examine and edit selected package items with psql without repeatedly typing `WHERE` qualifiers, joins, or specifying columns.

:grey_exclamation: This procedure relies on session settings and is unlikely to work with most external tools.

Assuming you imported the sample data packages, select the "gdp" package from the main schema (`pgtab`):

```
pgtab=> call go('gdp');
   selected
──────────────
 package: gdp
```

The [search_path](https://www.postgresql.org/docs/current/ddl-schemas.html#DDL-SCHEMAS-PATH) is changed to show views can be used to examine (and edit) elements of the JSON package:

- `p` - selected package
- `r` - package resources
- `readme` - package readme
- `description` - package readme
- `custom` - json elements not defined in the database


From a selected package, a resource can be selected:

```
pgtab=> call go('gdp');
          selected
─────────────────────────────
 package: gdp, resource: gdp
```

The resource's fields are listed in the `f` view:

```
pgtab=> table f;
 # │     name     │  type  │ title │    description     │ format
───┼──────────────┼────────┼───────┼────────────────────┼────────
 1 │ Country Name │ string │ •     │ •                  │ •
 2 │ Country Code │ string │ •     │ •                  │ •
 3 │ Year         │ year   │ •     │ •                  │ •
 4 │ Value        │ number │ •     │ GDP in current USD │ •
```

To select a field, call `go` with the field #:

```
pgtab=> call go(1);
                     selected
──────────────────────────────────────────────────
 package: gdp, resource: gdp, field: Country Name
```

To move up in the hierachy (package->resource->field) call `go` with an empty string:

```
pgtab=> call go('');
          selected
─────────────────────────────
 package: gdp, resource: gdp
 ```

Call `go` without parameters to return to the main schema.

Package and resources are searched with the `~~*` operator, which is case-insensitive and allows [wildcards](https://www.postgresql.org/docs/15/functions-matching.html#FUNCTIONS-LIKE).

```
pgtab=> call go('eu%');
               selected
──────────────────────────────────────
 package: eu-emissions-trading-system
```

