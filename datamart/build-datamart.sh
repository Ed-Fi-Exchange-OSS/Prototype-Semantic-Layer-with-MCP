#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

# Builds the early warning data mart from the Northridge sample data. Same steps as build-datamart.ps1:
#   1. Downloads the Northridge sample ODS (ODS/API 7.3, Data Standard 5.2) and restores it.
#   2. Moves its dates to the current school year (sql/time-travel.sql).
#   3. Installs the analytics views (sql/views) and their Northridge configuration (sql/descriptor-map.sql).
#   4. Builds the data mart database, with the views materialized into tables (sql/datamart.sql).
#
# Usage: ./build-datamart.sh [--refresh-only]
#   --refresh-only  only rebuilds the data mart from the ODS (step 4)

set -euo pipefail
cd "$(dirname "$0")"
# Git Bash on Windows would otherwise rewrite the container paths below
export MSYS_NO_PATHCONV=1

refresh_only=false
case "${1:-}" in
    --refresh-only) refresh_only=true ;;
    "") ;;
    *) echo "Usage: $0 [--refresh-only]" >&2; exit 1 ;;
esac

ods_db=EdFi_Ods_Northridge
datamart_db=edfi_datamart
northridge_file=EdFi_Ods_Northridge_v73_20241230_PG13.7z
# Same file as Ed-Fi-ODS-Implementation's DatabaseTemplate/Scripts/NorthridgePostgreSql.ps1
northridge_url="https://odsassets.blob.core.windows.net/public/Northridge/$northridge_file"
view_folders=(Base Asmt Ews Chrab RLS)

db() {
    # stdin from /dev/null, or docker would read the file list of the loop that calls this
    docker compose exec -T db sh -c "$1" < /dev/null
}

sql_file() {
    db "psql -U postgres -d $1 -v ON_ERROR_STOP=1 -q -1 -f '/sql/$2'"
}

echo "Starting PostgreSQL..."
docker compose up -d --wait

if [ "$refresh_only" = false ]; then
    if [ ! -f ".cache/$northridge_file" ]; then
        echo "Downloading $northridge_file (about 290 MB)..."
        mkdir -p .cache
        curl -fL -o ".cache/$northridge_file.part" "$northridge_url"
        mv ".cache/$northridge_file.part" ".cache/$northridge_file"
    fi

    echo "Restoring $ods_db..."
    db "apk add --no-cache 7zip > /dev/null"
    docker compose cp ".cache/$northridge_file" "db:/tmp/$northridge_file"
    db "psql -U postgres -v ON_ERROR_STOP=1 -c 'DROP DATABASE IF EXISTS \"$ods_db\"' \
        -c 'CREATE DATABASE \"$ods_db\"'"
    # The dump assigns an object to a role that doesn't exist here; that error is expected and harmless.
    db "7z e -so /tmp/$northridge_file | psql -U postgres -d $ods_db -q -o /dev/null 2> /tmp/restore.log; \
        rm /tmp/$northridge_file"

    echo "Moving the dates to the current school year..."
    sql_file "$ods_db" time-travel.sql

    echo "Installing the analytics views..."
    for folder in "${view_folders[@]}"; do
        # One file name has a space, so read the names line by line
        while IFS= read -r file; do
            sql_file "$ods_db" "views/$folder/$file"
        done < <(ls "sql/views/$folder" | grep '\.sql$' | sort)
    done
    sql_file "$ods_db" descriptor-map.sql
fi

echo "Building $datamart_db..."
db "psql -U postgres -tc \"SELECT 1 FROM pg_database WHERE datname = '$datamart_db'\" | grep -q 1 \
    || psql -U postgres -c 'CREATE DATABASE $datamart_db'"
# The password comes from the container's environment, so it never appears in a command line here.
db "psql -U postgres -d $datamart_db -q -v ods_db=$ods_db -v ods_user=postgres \
    -v ods_password=\"\$POSTGRES_PASSWORD\" -f /sql/datamart.sql"

echo "Done. Data mart: database $datamart_db, schema analytics."
