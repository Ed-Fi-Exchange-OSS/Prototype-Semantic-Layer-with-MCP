-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Configuration of the analytics views for the Northridge sample data. Run on the ODS after sql/views.
-- Each mapping links an Ed-Fi descriptor value to a constant the views use; running it again changes nothing.
--
-- Users: rls_UserDim builds one user per staff member from their work email (constant Email.Work), which
-- the default configuration maps only to the `Work` electronic mail type. Northridge staff emails use the
-- `Organization` type, so without this mapping there are no users and row-level security returns nothing.
--
-- Access scope: the default configuration gives teachers their sections, principals their school and the
-- superintendent the district. Northridge also has assistant principals, who get their school, and an LEA
-- administrator, who gets the district.

WITH mapping (constantname, namespace, codevalue) AS (VALUES
    ('Email.Work', 'uri://ed-fi.org/ElectronicMailTypeDescriptor', 'Organization'),
    ('AuthorizationScope.School', 'uri://ed-fi.org/StaffClassificationDescriptor', 'Assistant Principal'),
    ('AuthorizationScope.District', 'uri://ed-fi.org/StaffClassificationDescriptor', 'LEA Administrator')
)
INSERT INTO analytics_config.descriptormap (descriptorconstantid, descriptorid, createdate)
SELECT c.descriptorconstantid, d.descriptorid, now()
FROM mapping
JOIN analytics_config.descriptorconstant c ON c.constantname = mapping.constantname
JOIN edfi.descriptor d ON d.namespace = mapping.namespace AND d.codevalue = mapping.codevalue
WHERE NOT EXISTS (SELECT 1 FROM analytics_config.descriptormap m
                  WHERE m.descriptorconstantid = c.descriptorconstantid AND m.descriptorid = d.descriptorid);
