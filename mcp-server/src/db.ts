// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

import { readFileSync } from 'node:fs';
import pg from 'pg';

/** The SQL files the tools run, loaded once at startup. */
const sqlDir = new URL('../../sql/', import.meta.url);
const queries = new Map<string, string>();

export function sql(name: string): string {
    let text = queries.get(name);
    if (text === undefined) {
        text = readFileSync(new URL(`${name}.sql`, sqlDir), 'utf8');
        queries.set(name, text);
    }
    return text;
}

/**
 * Connection pool to the data mart. Connection settings come from the standard PG* environment variables or
 * DATAMART_DATABASE_URL. Every transaction is read-only, whatever the role allows.
 */
export const pool = new pg.Pool({
    connectionString: process.env.DATAMART_DATABASE_URL,
    max: 5,
    options: '-c default_transaction_read_only=on -c statement_timeout=10000',
});

export async function query<T extends pg.QueryResultRow>(name: string, params: unknown[]): Promise<T[]> {
    const result = await pool.query<T>(sql(name), params);
    return result.rows;
}
