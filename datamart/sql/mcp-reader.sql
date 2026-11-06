-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- The role the MCP server connects with: it can only read the analytics and lineage schemas of the data mart.
-- Run on the data mart database after sql/datamart.sql and sql/lineage.sql (the analytics tables are
-- recreated on every build).
-- psql variable: reader_password.

SELECT 'CREATE ROLE mcp_reader LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mcp_reader')
\gexec

ALTER ROLE mcp_reader WITH LOGIN PASSWORD :'reader_password';
ALTER ROLE mcp_reader SET default_transaction_read_only = on;
REVOKE ALL ON SCHEMA public FROM mcp_reader;
GRANT USAGE ON SCHEMA analytics TO mcp_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO mcp_reader;
GRANT USAGE ON SCHEMA lineage TO mcp_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA lineage TO mcp_reader;
