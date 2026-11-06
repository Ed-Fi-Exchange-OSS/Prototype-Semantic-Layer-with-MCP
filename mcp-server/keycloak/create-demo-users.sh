#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

# Creates the demo users in the Keycloak realm "edfi", with the emails of Northridge staff: a teacher, a
# principal, an assistant principal, the superintendent and the district administrator. Runs in the Keycloak
# image (see datamart/docker-compose.yml), once Keycloak is up. The users' password comes from
# DEMO_USER_PASSWORD and is set again on every run.

set -euo pipefail

kcadm=/opt/keycloak/bin/kcadm.sh
server=http://keycloak:8080

for attempt in $(seq 1 60); do
    if "$kcadm" config credentials --server "$server" --realm master \
        --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" > /dev/null 2>&1; then
        break
    fi
    [ "$attempt" -eq 60 ] && { echo "Keycloak didn't start" >&2; exit 1; }
    sleep 2
done

create_user() {
    # Keycloak stores usernames and emails in lower case
    local email=${1,,} first=$2 last=$3 id
    id=$("$kcadm" get users -r edfi -q "email=$email" -q exact=true --fields id --format csv --noquotes)
    if [ -z "$id" ]; then
        id=$("$kcadm" create users -r edfi -s "username=$email" -s "email=$email" -s emailVerified=true \
            -s enabled=true -s "firstName=$first" -s "lastName=$last" -i)
        echo "Created $email"
    fi
    "$kcadm" set-password -r edfi --userid "$id" --new-password "$DEMO_USER_PASSWORD"
}

create_user tina.blevins@RidgemontHighSchool.edu Tina Blevins
create_user carmen.helms@RidgemontHighSchool.edu Carmen Helms
create_user sheryl.horton@RidgemontHighSchool.edu Sheryl Horton
create_user superintendent@NorthridgeISD.edu Northridge Superintendent
create_user sysadmin@NorthridgeISD.edu Northridge Administrator
