// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

import { readFileSync } from 'node:fs';
import { createServer as createHttpServer } from 'node:http';
import { createServer as createHttpsServer } from 'node:https';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { authFromEnv } from './auth.js';
import { createMcpServer, createRequestHandler, userByEmail } from './http.js';

const port = Number(process.env.PORT ?? 3000);
// The demo user (DEMO_USER_EMAIL) stands in for the signed-in user when sign-in is off, and over stdio.
const demoUserEmail = process.env.DEMO_USER_EMAIL;

if (process.argv.includes('--stdio')) {
    await createMcpServer(userByEmail(demoUserEmail)).connect(new StdioServerTransport());
} else {
    const auth = authFromEnv(process.env, port);
    const handler = createRequestHandler({ auth, demoUserEmail });
    // HTTPS when given a certificate and key (TLS_CERT_FILE, TLS_KEY_FILE); plain HTTP otherwise, for
    // development.
    const certFile = process.env.TLS_CERT_FILE;
    const keyFile = process.env.TLS_KEY_FILE;
    const secure = Boolean(certFile && keyFile);
    const httpServer = secure
        ? createHttpsServer({ cert: readFileSync(certFile!), key: readFileSync(keyFile!) }, handler)
        : createHttpServer(handler);
    httpServer.listen(port, () => {
        console.error(`Early warning MCP server on ${secure ? 'https' : 'http'}://localhost:${port}/mcp`);
        console.error(auth
            ? `Sign-in: tokens from ${auth.issuer} for ${auth.resource}`
            : `Sign-in off: every request uses the demo user (${demoUserEmail ?? 'none'})`);
    });
}
