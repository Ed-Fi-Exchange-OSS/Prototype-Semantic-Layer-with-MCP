-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- The data mart user for an email address. $1: email.

SELECT userkey
FROM analytics.rls_userdim
WHERE lower(useremail) = lower($1)
LIMIT 1;
