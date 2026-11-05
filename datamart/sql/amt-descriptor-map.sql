-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Analytics Middle Tier configuration for the Northridge sample data. Run on the ODS after installing AMT.
--
-- rls_UserDim builds one user per staff member from their work email (constant Email.Work), which AMT maps
-- only to the `Work` electronic mail type. Northridge staff emails use the `Organization` type, so without
-- this mapping there are no users and row-level security returns nothing.

INSERT INTO analytics_config.descriptormap (descriptorconstantid, descriptorid, createdate)
SELECT c.descriptorconstantid, d.descriptorid, now()
FROM analytics_config.descriptorconstant c
CROSS JOIN edfi.descriptor d
WHERE c.constantname = 'Email.Work'
  AND d.namespace = 'uri://ed-fi.org/ElectronicMailTypeDescriptor'
  AND d.codevalue = 'Organization'
  AND NOT EXISTS (SELECT 1 FROM analytics_config.descriptormap m
                  WHERE m.descriptorconstantid = c.descriptorconstantid AND m.descriptorid = d.descriptorid);
