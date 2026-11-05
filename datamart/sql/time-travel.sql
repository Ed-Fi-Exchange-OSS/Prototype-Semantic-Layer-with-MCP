-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Moves an Ed-Fi ODS (PostgreSQL) to the current school year.
-- Port of Ed-Fi-Exchange-OSS/Ed-Fi-Sample-Data-Time-Travel-Script (T-SQL) to PostgreSQL, with these changes:
--   * dates move by a whole number of weeks, so weekdays and the intervals between dates are kept;
--   * year columns move only when they hold a year, not *descriptorid or *schoolid columns whose name
--     contains "year";
--   * null years stay null (the original filled them with the existing school year);
--   * edfi.schoolyeartype keeps its rows (it already lists 1991-2050); only the current school year flag
--     moves.
-- Run as a superuser on a copy of the database: it disables foreign key checks and triggers while it runs.

SET session_replication_role = replica;

DO $$
DECLARE
    target_year   smallint := CASE WHEN extract(month FROM now()) >= 7
                                   THEN extract(year FROM now())::smallint + 1
                                   ELSE extract(year FROM now())::smallint END;
    existing_year smallint := (SELECT max(schoolyear) FROM edfi.calendar);
    year_diff     smallint := target_year - existing_year;
    shift_days    integer  := round(year_diff * 365.2425 / 7) * 7;
    col record;
BEGIN
    IF year_diff <= 0 THEN
        RAISE NOTICE 'Already at school year %, nothing to do', existing_year;
        RETURN;
    END IF;
    RAISE NOTICE 'Moving school year % to % (% years, % days)',
        existing_year, target_year, year_diff, shift_days;

    FOR col IN
        SELECT c.table_schema, c.table_name, c.column_name, c.data_type
        FROM information_schema.columns c
        JOIN information_schema.tables t USING (table_schema, table_name)
        WHERE t.table_type = 'BASE TABLE'
          AND c.table_schema NOT IN
              ('pg_catalog', 'information_schema', 'public', 'analytics_config')
          AND c.column_name NOT IN ('createdate', 'lastmodifieddate')
          AND NOT (c.table_schema = 'edfi' AND c.table_name = 'schoolyeartype')
          AND (
                (c.column_name LIKE '%date%'
                 AND c.data_type IN ('date', 'timestamp without time zone', 'timestamp with time zone'))
             OR (c.column_name LIKE '%year%'
                 AND c.data_type IN ('smallint', 'integer')
                 AND c.column_name NOT LIKE '%descriptorid'
                 AND c.column_name NOT LIKE '%schoolid')
              )
        ORDER BY 1, 2, 3
    LOOP
        IF col.data_type IN ('smallint', 'integer') THEN
            EXECUTE format('UPDATE %I.%I SET %I = %I + %s WHERE %I IS NOT NULL',
                           col.table_schema, col.table_name, col.column_name, col.column_name, year_diff,
                           col.column_name);
        ELSE
            EXECUTE format('UPDATE %I.%I SET %I = %I + interval ''%s days'' WHERE %I IS NOT NULL',
                           col.table_schema, col.table_name, col.column_name, col.column_name, shift_days,
                           col.column_name);
        END IF;
    END LOOP;

    UPDATE edfi.schoolyeartype SET currentschoolyear = (schoolyear = target_year);
END $$;

SET session_replication_role = origin;
