# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

<#
.SYNOPSIS
    Builds the early warning data mart from the Northridge sample data.

.DESCRIPTION
    Runs everything in the PostgreSQL container from docker-compose.yml:
    1. Downloads the Northridge sample ODS (ODS/API 7.3, Data Standard 5.2) and restores it.
    2. Moves its dates to the current school year (sql/time-travel.sql).
    3. Installs the analytics views (sql/views) and their Northridge configuration
       (sql/descriptor-map.sql).
    4. Builds the data mart database, with the views materialized into tables (sql/datamart.sql).

.PARAMETER RefreshOnly
    Only rebuilds the data mart from the ODS (step 4).
#>
param(
    [switch] $RefreshOnly
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$OdsDb = 'EdFi_Ods_Northridge'
$DataMartDb = 'edfi_datamart'
$NorthridgeFile = 'EdFi_Ods_Northridge_v73_20241230_PG13.7z'
# Same file as Ed-Fi-ODS-Implementation's DatabaseTemplate/Scripts/NorthridgePostgreSql.ps1
$NorthridgeUrl = "https://odsassets.blob.core.windows.net/public/Northridge/$NorthridgeFile"
$ViewFolders = 'Base', 'Asmt', 'Ews', 'Chrab', 'RLS'

function Invoke-Db {
    param([string] $Command)
    docker compose exec -T db sh -c $Command
    if ($LASTEXITCODE -ne 0) { throw "Failed: $Command" }
}

function Invoke-SqlFile {
    param([string] $Database, [string] $Path)
    Invoke-Db "psql -U postgres -d $Database -v ON_ERROR_STOP=1 -q -1 -f '/sql/$Path'"
}

Write-Host 'Starting PostgreSQL...'
docker compose up -d --wait
if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed' }

if (-not $RefreshOnly) {
    if (-not (Test-Path ".cache/$NorthridgeFile")) {
        Write-Host "Downloading $NorthridgeFile (about 290 MB)..."
        New-Item -ItemType Directory -Force .cache | Out-Null
        Invoke-WebRequest -Uri $NorthridgeUrl -OutFile ".cache/$NorthridgeFile"
    }

    Write-Host "Restoring $OdsDb..."
    Invoke-Db 'apk add --no-cache 7zip > /dev/null'
    docker compose cp ".cache/$NorthridgeFile" "db:/tmp/$NorthridgeFile"
    if ($LASTEXITCODE -ne 0) { throw 'docker compose cp failed' }
    Invoke-Db ("psql -U postgres -v ON_ERROR_STOP=1 " +
        "-c 'DROP DATABASE IF EXISTS `"$OdsDb`"' -c 'CREATE DATABASE `"$OdsDb`"'")
    # The dump assigns an object to a role that doesn't exist here; that error is expected and harmless.
    Invoke-Db ("7z e -so /tmp/$NorthridgeFile | psql -U postgres -d $OdsDb -q -o /dev/null 2> /tmp/restore.log; " +
        "rm /tmp/$NorthridgeFile")

    Write-Host 'Moving the dates to the current school year...'
    Invoke-SqlFile $OdsDb 'time-travel.sql'

    Write-Host 'Installing the analytics views...'
    foreach ($folder in $ViewFolders) {
        Get-ChildItem "sql/views/$folder/*.sql" | Sort-Object Name | ForEach-Object {
            Invoke-SqlFile $OdsDb "views/$folder/$($_.Name)"
        }
    }
    Invoke-SqlFile $OdsDb 'descriptor-map.sql'
}

Write-Host "Building $DataMartDb..."
Invoke-Db ("psql -U postgres -tc `"SELECT 1 FROM pg_database WHERE datname = '$DataMartDb'`" | grep -q 1 " +
    "|| psql -U postgres -c 'CREATE DATABASE $DataMartDb'")
# The password comes from the container's environment, so it never appears in a command line here.
Invoke-Db ("psql -U postgres -d $DataMartDb -q -v ods_db=$OdsDb -v ods_user=postgres " +
    "-v ods_password=`"`$POSTGRES_PASSWORD`" -f /sql/datamart.sql")

Write-Host "Done. Data mart: database $DataMartDb, schema analytics."
