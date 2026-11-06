// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

import type { IncomingMessage } from 'node:http';
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

/**
 * Sign-in settings. The MCP server is an OAuth resource server: it only checks access tokens that the
 * authorization server (Keycloak) issued for it, and takes the user from the token's verified email.
 */
export interface AuthConfig {
    /** The authorization server's issuer, as it appears in tokens. */
    issuer: string;
    /** This server's resource identifier, which tokens must carry as audience. */
    resource: string;
    /** Where to read the issuer's signing keys (may differ from the issuer inside Docker). */
    jwksUrl: URL;
    /** URL of this server's protected resource metadata (RFC 9728). */
    resourceMetadataUrl: string;
    /** The current time, for tests; the system clock by default. */
    now?: () => Date;
}

/**
 * Sign-in settings from OAUTH_ISSUER, MCP_RESOURCE_URL and OAUTH_JWKS_URL; none when OAUTH_ISSUER is empty.
 */
export function authFromEnv(env: NodeJS.ProcessEnv, port: number): AuthConfig | undefined {
    const issuer = env.OAUTH_ISSUER?.replace(/\/$/, '');
    if (!issuer) {
        return undefined;
    }
    const resource = env.MCP_RESOURCE_URL ?? `https://localhost:${port}/mcp`;
    const { origin, pathname } = new URL(resource);
    return {
        issuer,
        resource,
        jwksUrl: new URL(env.OAUTH_JWKS_URL ?? `${issuer}/protocol/openid-connect/certs`),
        resourceMetadataUrl: `${origin}/.well-known/oauth-protected-resource${pathname}`,
    };
}

/** Protected resource metadata (RFC 9728): tells MCP clients where users sign in. */
export function resourceMetadata(config: AuthConfig) {
    return {
        resource: config.resource,
        authorization_servers: [config.issuer],
        bearer_methods_supported: ['header'],
        resource_name: 'Ed-Fi early warning MCP server',
    };
}

export type AuthResult =
    | { ok: true; email: string }
    | { ok: false; wwwAuthenticate: string };

const keySets = new Map<string, JWTVerifyGetKey>();

/** Checks the request's bearer token: signature, issuer, audience, expiry, and a verified email. */
export async function authenticate(req: IncomingMessage, config: AuthConfig): Promise<AuthResult> {
    const challenge = `Bearer resource_metadata="${config.resourceMetadataUrl}"`;
    const header = req.headers.authorization ?? '';
    const match = /^Bearer (\S+)$/i.exec(header);
    if (!match) {
        return { ok: false, wwwAuthenticate: challenge };
    }
    let keys = keySets.get(config.jwksUrl.href);
    if (!keys) {
        keys = createRemoteJWKSet(config.jwksUrl);
        keySets.set(config.jwksUrl.href, keys);
    }
    const invalid = (description: string) => ({
        ok: false as const,
        wwwAuthenticate: `${challenge}, error="invalid_token", error_description="${description}"`,
    });
    try {
        const { payload } = await jwtVerify(match[1], keys, {
            issuer: config.issuer,
            audience: config.resource,
            clockTolerance: 30,
            currentDate: config.now?.(),
        });
        if (typeof payload.email !== 'string' || payload.email_verified !== true) {
            return invalid('The token has no verified email');
        }
        return { ok: true, email: payload.email };
    } catch {
        // Don't echo the reason: it would help someone probing with forged tokens
        return invalid('The token is not valid for this server');
    }
}
