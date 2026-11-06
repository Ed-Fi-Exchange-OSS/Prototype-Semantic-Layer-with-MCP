// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

// Manual sign-in check: plays the MCP client's part of the authorization code flow with PKCE.
// 1. Finds the authorization server from the MCP server's protected resource metadata.
// 2. Prints the authorization URL: open it in a browser and sign in as a demo user.
// 3. Receives the code on http://127.0.0.1:33418/callback, exchanges it for a token, and calls the MCP server
//    as the signed-in user.
// Run from mcp-server/, with NODE_EXTRA_CA_CERTS pointing to certs/server.crt.

import { createHash, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const mcpUrl = process.env.MCP_URL ?? 'https://localhost:3000/mcp';
const redirectUri = 'http://127.0.0.1:33418/callback';
const verifier = randomBytes(32).toString('base64url');
const challenge = createHash('sha256').update(verifier).digest('base64url');
const state = randomBytes(8).toString('hex');

const { origin, pathname } = new URL(mcpUrl);
const resource = await (await fetch(`${origin}/.well-known/oauth-protected-resource${pathname}`)).json();
const issuer = resource.authorization_servers[0];
const server = await (await fetch(`${issuer}/.well-known/openid-configuration`)).json();
console.log(`Authorization server: ${issuer}`);
console.log(`Sign in here:\n${server.authorization_endpoint}?${new URLSearchParams({
    client_id: 'edfi-mcp', response_type: 'code', redirect_uri: redirectUri, scope: 'openid email', state,
    code_challenge: challenge, code_challenge_method: 'S256',
})}`);

createServer(async (req, res) => {
    const url = new URL(req.url, redirectUri);
    if (url.pathname !== '/callback') {
        res.writeHead(404).end();
        return;
    }
    if (url.searchParams.get('state') !== state) {
        res.writeHead(400).end('Unexpected state');
        return;
    }
    const tokenResponse = await fetch(server.token_endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            grant_type: 'authorization_code', client_id: 'edfi-mcp', code: url.searchParams.get('code'),
            redirect_uri: redirectUri, code_verifier: verifier,
        }),
    });
    const { access_token: accessToken } = await tokenResponse.json();
    const claims = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64url').toString());
    console.log(`Token: ${JSON.stringify({ iss: claims.iss, aud: claims.aud, azp: claims.azp,
        email: claims.email, email_verified: claims.email_verified })}`);

    const client = new Client({ name: 'pkce-flow', version: '0.0.0' });
    await client.connect(new StreamableHTTPClientTransport(new URL(mcpUrl), {
        requestInit: { headers: { Authorization: `Bearer ${accessToken}` } },
    }));
    const scope = await client.callTool({ name: 'get_my_scope', arguments: {} });
    console.log(`get_my_scope: ${scope.content[0].text}`);
    const risk = JSON.parse((await client.callTool({ name: 'list_students_at_risk',
        arguments: { limit: 3 } })).content[0].text);
    console.log(`list_students_at_risk: ${risk.students.map(s => `${s.name} (${s.indicators})`).join(', ')}`);
    await client.close();
    res.writeHead(200, { 'Content-Type': 'text/plain' }).end('Signed in. You can close this tab.');
    setTimeout(() => process.exit(0), 200);
}).listen(33418, '127.0.0.1');
