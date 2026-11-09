// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

// Sign-in: runs the HTTP handler in this process, with real tokens from the local Keycloak (see
// ../README.md). Needs DEMO_USER_PASSWORD and, for the self-signed certificate, NODE_EXTRA_CA_CERTS.

import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, describe, mock, test } from 'node:test';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { generateKeyPair, SignJWT } from 'jose';
import { pool } from '../src/db.js';
import { createRequestHandler } from '../src/http.js';
import type { AuthConfig } from '../src/auth.js';

const keycloak = process.env.KEYCLOAK_URL ?? 'https://localhost:8443';
const issuer = `${keycloak}/realms/edfi`;
const resource = 'https://localhost:3000/mcp';
const password = process.env.DEMO_USER_PASSWORD;
const teacher = 'tina.blevins@RidgemontHighSchool.edu';
const principal = 'carmen.helms@RidgemontHighSchool.edu';
const assistantPrincipal = 'sheryl.horton@RidgemontHighSchool.edu';
const superintendent = 'superintendent@NorthridgeISD.edu';
const districtAdministrator = 'sysadmin@NorthridgeISD.edu';

async function token(username: string, clientId = 'edfi-mcp-tests'): Promise<string> {
    const response = await fetch(`${issuer}/protocol/openid-connect/token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            grant_type: 'password', client_id: clientId, username, password: password!,
        }),
    });
    const body = await response.json() as { access_token?: string };
    assert.ok(body.access_token, `token for ${username} from ${clientId}`);
    return body.access_token;
}

describe('sign-in', { skip: password ? false : 'DEMO_USER_PASSWORD is not set' }, () => {
    let server: Server;
    let url: string;
    let auth: AuthConfig;

    before(async () => {
        auth = {
            issuer,
            resource,
            jwksUrl: new URL(`${issuer}/protocol/openid-connect/certs`),
            resourceMetadataUrl: 'https://localhost:3000/.well-known/oauth-protected-resource/mcp',
        };
        server = createServer(createRequestHandler({ auth, demoUserEmail: teacher }));
        await new Promise<void>(resolve => server.listen(0, resolve));
        url = `http://localhost:${(server.address() as AddressInfo).port}`;
    });

    after(async () => {
        server.close();
        await pool.end();
    });

    async function post(headers: Record<string, string> = {}) {
        return fetch(`${url}/mcp`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Accept: 'application/json, text/event-stream',
                ...headers,
            },
            body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
        });
    }

    async function connect(accessToken: string): Promise<Client> {
        const client = new Client({ name: 'test-client', version: '0.0.0' });
        await client.connect(new StreamableHTTPClientTransport(new URL(`${url}/mcp`), {
            requestInit: { headers: { Authorization: `Bearer ${accessToken}` } },
        }));
        return client;
    }

    async function scopeOf(client: Client) {
        const response = await client.callTool({ name: 'get_my_scope', arguments: {} });
        return JSON.parse((response.content as { text: string }[])[0].text);
    }

    test('publishes protected resource metadata that points to Keycloak', async () => {
        const response = await fetch(`${url}/.well-known/oauth-protected-resource/mcp`);
        assert.equal(response.status, 200);
        const metadata = await response.json();
        assert.equal(metadata.resource, resource);
        assert.deepEqual(metadata.authorization_servers, [issuer]);
    });

    test('a request without a token gets 401 and where to sign in, not the demo user', async () => {
        const response = await post();
        assert.equal(response.status, 401);
        const challenge = response.headers.get('www-authenticate') ?? '';
        assert.ok(challenge.startsWith(`Bearer resource_metadata="${auth.resourceMetadataUrl}"`), challenge);
    });

    test('rejects a malformed token, a forged token and a token for another audience', async () => {
        const { privateKey } = await generateKeyPair('RS256');
        const forged = await new SignJWT({ email: teacher, email_verified: true })
            .setProtectedHeader({ alg: 'RS256', kid: 'forged' })
            .setIssuer(issuer).setAudience(resource).setIssuedAt().setExpirationTime('5m')
            .sign(privateKey);
        const otherAudience = await token(teacher, 'admin-cli');
        const log = mock.method(console, 'error', () => {});
        try {
            for (const [name, value, reason] of [['malformed', 'not-a-token', /ERR_JWS_INVALID/],
                ['forged', forged, /ERR_JWKS_NO_MATCHING_KEY/],
                ['another audience', otherAudience, /ERR_JWT_CLAIM_VALIDATION_FAILED: .*"aud"/]] as const) {
                const response = await post({ Authorization: `Bearer ${value}` });
                assert.equal(response.status, 401, name);
                const challenge = response.headers.get('www-authenticate') ?? '';
                assert.match(challenge, /error="invalid_token"/, name);
                // The server logs why, but the response doesn't say, and neither shows the token
                const logged = String(log.mock.calls.at(-1)?.arguments[0]);
                assert.match(logged, reason, name);
                assert.ok(!logged.includes(value) && !challenge.includes(value), name);
                assert.doesNotMatch(challenge, /aud|ERR_/, name);
            }
        } finally {
            log.mock.restore();
        }
    });

    test('rejects an expired token', async () => {
        const accessToken = await token(teacher);
        const { exp } = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64url').toString());
        // Present the token two minutes after it expired, past the clock tolerance
        auth.now = () => new Date((exp + 120) * 1000);
        try {
            const response = await post({ Authorization: `Bearer ${accessToken}` });
            assert.equal(response.status, 401);
            assert.match(response.headers.get('www-authenticate') ?? '', /error="invalid_token"/);
        } finally {
            delete auth.now;
        }
    });

    test('each signed-in user sees their own scope', async () => {
        const expected: [string, string][] = [
            [teacher, 'Section'], [principal, 'School'], [assistantPrincipal, 'School'],
            [superintendent, 'District'], [districtAdministrator, 'District'],
        ];
        for (const [email, scopeName] of expected) {
            const [{ students }] = (await pool.query(
                `SELECT count(*)::int AS students FROM analytics.rls_userstudentdataauthorization a
                 JOIN analytics.rls_userdim u ON u.userkey = a.userkey
                 WHERE lower(u.useremail) = lower($1)`, [email])).rows;
            assert.ok(students > 0, email);
            const client = await connect(await token(email));
            const scope = await scopeOf(client);
            assert.equal(scope.email.toLowerCase(), email.toLowerCase());
            assert.equal(scope.scopes[0].scope, scopeName, email);
            assert.equal(scope.students, students, email);
            await client.close();
        }
    });

    test('the signed-in user, not the demo user, decides what comes back', async () => {
        const client = await connect(await token(principal));
        const scope = await scopeOf(client);
        assert.notEqual(scope.email.toLowerCase(), teacher.toLowerCase());
        await client.close();
    });
});
