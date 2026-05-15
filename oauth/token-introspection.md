---
name: oauth-token-introspection
description: OAuth 2.0 Token Introspection (RFC 7662) — pattern d'introspection d'un access_token opaque par un Resource Server / API Gateway. Compare avec JWT local validation. Bonnes pratiques cache, sécurité, performances.
type: reference
---

# OAuth 2.0 Token Introspection (RFC 7662)

Pattern où un Resource Server (RS) ou un API Gateway demande à l'Authorization Server (AS) de valider un `access_token` opaque, plutôt que de le valider localement. Spec : [RFC 7662 — OAuth 2.0 Token Introspection](https://datatracker.ietf.org/doc/html/rfc7662).

## Quand introspecter vs valider localement (JWT)

| Aspect | Introspection RFC 7662 | JWT validation locale |
|---|---|---|
| Type de token | Opaque (référence) ou JWT | JWT signé (JWS) |
| Validation | Appel HTTP à l'AS | Vérification signature locale via JWKS |
| Latence | +1 round-trip par requête (mitigable par cache) | Très rapide (parsing + vérif crypto) |
| Révocation | Immédiate (l'AS connaît l'état) | Délai jusqu'à expiration du token (sauf revocation list) |
| Confidentialité | Tokens opaques → claims jamais exposés au client | JWT lisible par le client (claims publics) |
| Couplage AS / RS | Fort (chaque requête appelle l'AS) | Faible (JWKS rafraîchi périodiquement) |
| Coût opérationnel AS | Haut (montée en charge proportionnelle au trafic) | Faible |

**Règle empirique** : introspection si la **révocation immédiate** est critique (auth d'agents internes, sessions sensibles), ou si l'organisation souhaite **opaque tokens** (pas de claims dans le client). JWT local si latence et scaling priment.

## Format de la requête introspection (RFC 7662 §2)

```http
POST /introspect HTTP/1.1
Host: authorization-server.example.com
Authorization: Basic <base64(client_id:client_secret)>
Content-Type: application/x-www-form-urlencoded

token=mF_9.B5f-4.1JqM&token_type_hint=access_token
```

## Format de la réponse (RFC 7662 §2.2)

```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "active": true,
  "scope": "read write",
  "client_id": "client-id-value",
  "username": "alice",
  "token_type": "Bearer",
  "exp": 1419356238,
  "iat": 1419350238,
  "sub": "Z5O3upPC88QrAjx00dis",
  "aud": "https://protected-resource.example.com/",
  "iss": "https://authorization-server.example.com/",
  "jti": "JlbmMiOiJBMTI4Q0JDLUhTMjU2In"
}
```

Champ minimal : `active` (booléen). Si `false`, le token est invalide/révoqué/expiré → réponse 401 au client.

## Cache d'introspection — critique pour la perf

Sans cache, **chaque requête au RS** déclenche un appel à l'AS → goulet d'étranglement. Cache typique :

| Niveau | TTL | Note |
|---|---|---|
| Cache local (mémoire) | 30-60s | Suffit pour la majorité des cas single-instance |
| Cache distribué (Redis, Memcached) | 60-300s | Indispensable en multi-replicas (sinon cohérence imparfaite) |
| Cache "negative" (token invalide) | 10-30s | Évite de spam l'AS avec des tokens connus invalides |

⚠️ **Trade-off cache vs révocation** : plus le TTL est long, plus une révocation côté AS prend du temps à se propager. Ajuster selon le risque métier.

## Performance — réutiliser la connexion HTTP

L'appel à l'AS doit utiliser un **pool HTTP keep-alive** (et idéalement HTTP/2 multiplexé). Sinon chaque introspection paye un handshake TCP/TLS — facilement >50ms par requête.

## Sécurité

- 🔒 Le `client_secret` du Resource Server doit être stocké dans un coffre (Vault, Conjur, AWS Secrets Manager), **jamais dans le code**.
- 🔒 L'endpoint `/introspect` est protégé par authentification client (Basic Auth, mTLS, JWT client). Sinon n'importe qui pourrait valider/sonder des tokens.
- 🔒 La réponse d'introspection contient des données potentiellement sensibles (`sub`, `username`, `email`) — limiter le scope des claims exposés.
- 🔒 ⚠️ **Ne pas introspecter à chaque hop** d'un appel inter-services. Faire confiance aux claims propagés par le gateway (header `X-User-Id` etc., en authentifiant la chaîne via mTLS).

## Cas d'usage — Gateway / BFF

Pattern courant : un **API Gateway** introspecte le token opaque reçu du client, puis :
1. Valide la réponse (`active: true`, `scope` couvre la route demandée, `aud` cohérent)
2. Met en cache la réponse (Redis pour multi-replicas)
3. Propage les claims utiles vers les services back via des headers signés (`X-User-Id`, `X-User-Email`, `X-Scopes`)
4. Les services back **n'introspectent pas** ; ils font confiance aux headers car le réseau interne est sécurisé (mTLS, NetworkPolicy)

C'est le pattern adopté notamment par Spring Cloud Gateway (`OAuth2ResourceServer` ou filtre custom), Kong (plugin OAuth2 Introspection), Envoy (ext_authz filter).

## Anti-patterns

- ❌ **Introspecter sans cache** → goulet d'étranglement immédiat.
- ❌ **Cache trop long** (>5 min) → révocation différée trop longtemps.
- ❌ **Introspecter à chaque hop interne** → coût × nombre de services.
- ❌ **Stocker `client_secret` dans le repo** ou `application.yml` clear.
- ❌ **Ignorer `aud` et `scope`** dans la réponse → un token valide pour le service A pourrait être accepté par le service B.
- ❌ **Pas de fallback en cas d'AS down** → toute la plateforme s'écroule si l'AS est inaccessible (mettre un timeout court + une stratégie : fail-closed strict ou fail-open avec audit).

## Ressources

| Source | URL |
|---|---|
| RFC 7662 — OAuth 2.0 Token Introspection | https://datatracker.ietf.org/doc/html/rfc7662 |
| RFC 6749 — OAuth 2.0 Authorization Framework | https://datatracker.ietf.org/doc/html/rfc6749 |
| RFC 7519 — JSON Web Token (JWT) | https://datatracker.ietf.org/doc/html/rfc7519 |
| RFC 7517 — JSON Web Key Set (JWKS) | https://datatracker.ietf.org/doc/html/rfc7517 |
| OAuth 2.0 Security Best Current Practice | https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics |
| Spring Security — OAuth2 Resource Server (introspection mode) | https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/opaque-token.html |
