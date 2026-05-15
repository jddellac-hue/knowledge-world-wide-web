---
name: spring-cloud-gateway
description: Spring Cloud Gateway (SCG) 4.x — framework API Gateway réactif sur Spring WebFlux. Routes, prédicats, filtres natifs, custom filters, mode reactive, intégration Spring Security. Pour tout sujet SCG hors contexte d'une entreprise spécifique.
type: reference
---

# Spring Cloud Gateway — Skill Reference

> Spring Cloud Gateway 4.x · Spring Framework 6.x+ · Java 17+ · Mode reactive (WebFlux)
> Last updated: 2026-05-12

## Quand utiliser SCG

Spring Cloud Gateway est un **API Gateway réactif** construit sur Spring WebFlux et Reactor Netty. À comparer à :

| Outil | Quand |
|---|---|
| **Spring Cloud Gateway** | Routes définies en YAML/Java, filtres extensibles en Java, intégration Spring Security, mode reactive natif, équipe Spring |
| Kong / Tyk / KrakenD | Configuration centralisée par UI/API, plugins Lua, déploiement multi-équipes |
| Envoy / Istio Gateway | Service mesh, configuration via CRD K8S, observabilité avancée |
| NGINX / HAProxy | L4/L7 simple, hautes performances, conf via fichier statique |
| Spring Cloud Netflix Zuul | ⚠️ Deprecated — SCG est son successeur |

## Architecture

```
Client
  │
  ▼
┌────────────────────────────────────────────────────┐
│ Gateway Handler Mapping                            │
│ (matche la requête à une Route)                    │
└────────────────────────────────────────────────────┘
  │
  ▼
┌────────────────────────────────────────────────────┐
│ Route — id, uri, predicates, filters               │
│ ┌──────────────────────────────────────────────┐   │
│ │ Pre-filters (modify request)                 │   │
│ └──────────────────────────────────────────────┘   │
│ ┌──────────────────────────────────────────────┐   │
│ │ Proxy filter (call downstream)               │   │
│ └──────────────────────────────────────────────┘   │
│ ┌──────────────────────────────────────────────┐   │
│ │ Post-filters (modify response)               │   │
│ └──────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
  │
  ▼
Downstream service
```

3 concepts clés :
- **Route** — destination (URI), avec ID unique, prédicats et filtres
- **Predicate** — condition de matching (Path, Host, Method, Header, Query, etc.)
- **Filter** — modification de la requête/réponse, en pré ou post

## Configuration YAML basique

```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: users_route
          uri: http://users-service:8080
          predicates:
            - Path=/api/users/**
            - Method=GET,POST
            - Host=**.example.com
          filters:
            - RewritePath=/api/users/(?<segment>.*), /$\{segment}
            - AddRequestHeader=X-Request-Source, gateway
            - CircuitBreaker=name=usersCB,fallbackUri=forward:/fallback
```

## Prédicats principaux ([doc officielle](https://docs.spring.io/spring-cloud-gateway/reference/spring-cloud-gateway-server-webflux/request-predicates-factories.html))

| Predicate | Exemple |
|---|---|
| `Path=` | `Path=/foo/{segment},/bar/**` |
| `Method=` | `Method=GET,POST` |
| `Host=` | `Host=**.example.com` |
| `Header=` | `Header=X-Request-Id, \d+` |
| `Query=` | `Query=foo, ba.` |
| `Cookie=` | `Cookie=mycookie, mycookievalue` |
| `After=` / `Before=` / `Between=` | Activation par fenêtre temporelle |
| `RemoteAddr=` | `RemoteAddr=192.168.1.1/24` |
| `Weight=` | Répartition pondérée entre routes |

## Filtres natifs principaux ([doc officielle](https://docs.spring.io/spring-cloud-gateway/reference/spring-cloud-gateway-server-webflux/gatewayfilter-factories.html))

| Filtre | Usage |
|---|---|
| `AddRequestHeader=` / `AddResponseHeader=` | Ajouter un header |
| `RemoveRequestHeader=` / `RemoveResponseHeader=` | Retirer un header |
| `SetRequestHeader=` / `SetResponseHeader=` | Forcer la valeur d'un header |
| `RewritePath=` | Réécriture du path (regex) |
| `StripPrefix=` | Retirer N segments en tête du path |
| `PrefixPath=` | Préfixer le path |
| `RedirectTo=` | Redirection HTTP |
| `CircuitBreaker=` | Resilience4j ou Hystrix |
| `RequestRateLimiter=` | Rate limiting avec KeyResolver custom (Redis-backed via Reactor Redis) |
| `Retry=` | Retry HTTP avec backoff |
| `RequestSize=` | Taille max de la requête |
| `ModifyRequestBody=` / `ModifyResponseBody=` | Transformation du corps (DTO ↔ DTO) |

## Filtres custom — `GatewayFilterFactory`

Pour un filtre métier, étendre `AbstractGatewayFilterFactory` :

```java
@Component
public class TokenValidationFilter
    extends AbstractGatewayFilterFactory<TokenValidationFilter.Config> {

    public TokenValidationFilter() {
        super(Config.class);
    }

    @Override
    public GatewayFilter apply(Config config) {
        return (exchange, chain) -> {
            String token = exchange.getRequest()
                .getHeaders().getFirst("Authorization");
            // validation logic ...
            return chain.filter(exchange);
        };
    }

    public static class Config {
        private String introspectUrl;
        // getters / setters
    }
}
```

Référence dans `application.yml` :

```yaml
filters:
  - name: TokenValidation
    args:
      introspectUrl: https://idp.example.com/introspect
```

## Mode reactive (WebFlux)

SCG **n'est pas Servlet-based** : il s'appuie sur Reactor Netty et Spring WebFlux. Conséquences :

- ⚠️ Ne pas bloquer le thread Reactor — pas de `Thread.sleep`, pas de JDBC bloquant dans un filtre. Utiliser `Mono` / `Flux` partout.
- Tooling Spring Web (`@Controller`) **incompatible** ; utiliser `@RestController` avec retour `Mono<...>` / `Flux<...>` ou `RouterFunction` pour exposer des endpoints internes (actuator, health).
- Métriques Micrometer émises avec préfixe `spring.cloud.gateway.*` et `http.server.requests.*` (compatibles Prometheus, OpenTelemetry).

## Intégration Spring Security

SCG fronte typiquement des services REST. Pour authentification :
- **Forward token** — SCG laisse passer le `Authorization` tel quel ; chaque service back valide lui-même → simple mais N×validations.
- **Centralised validation** — SCG valide via `OAuth2ResourceServer` ou un filtre custom (token introspection RFC 7662 ou JWT validation locale via JWKS) → les services back peuvent faire confiance aux claims propagés en headers.
- **Cookie session** — gateway agit comme BFF (Backend For Frontend) : reçoit cookie, valide la session, propage un token signé court terme vers le back.

Voir [token-introspection.md](../oauth/token-introspection.md) pour le pattern d'introspection.

## Observabilité

| Aspect | Mécanisme |
|---|---|
| Métriques | Micrometer (Prometheus, OpenTelemetry) — `http.server.requests.*` et `spring.cloud.gateway.*` |
| Logs | Logback / SLF4J — config `logging.level.org.springframework.cloud.gateway=DEBUG` pour debug routes |
| Traces | Micrometer Tracing (Brave / OpenTelemetry) — propagation B3 / W3C `traceparent` |
| Healthcheck | `actuator/health`, `actuator/gateway/routes` |

## Anti-patterns

- ❌ **Logique métier dans un filtre** — un filtre doit transformer/router, pas porter de règle métier (cohérence transactionnelle, business decision). Le métier reste dans le back.
- ❌ **Bloquer le thread Reactor** — `Thread.sleep`, JDBC synchrone, calls HTTP synchrones depuis un filtre.
- ❌ **Routes dynamiques sans test** — la configuration peut être très expressive ; tester les routes (intégration ou contract test).
- ❌ **Ignorer le sizing Reactor Netty** — `reactor.netty.ioWorkerCount`, `maxConnections` doivent être dimensionnés au trafic.
- ❌ **Rate limiting sans backend distribué** — `RequestRateLimiter` en mémoire échoue avec plusieurs replicas ; utiliser un Redis backend.

## Ressources

| Source | URL |
|---|---|
| Spring Cloud Gateway — Reference (officiel) | https://docs.spring.io/spring-cloud-gateway/reference/ |
| GitHub — `spring-cloud/spring-cloud-gateway` | https://github.com/spring-cloud/spring-cloud-gateway |
| Spring WebFlux | https://docs.spring.io/spring-framework/reference/web/webflux.html |
| Project Reactor | https://projectreactor.io/docs |
| Resilience4j (CircuitBreaker) | https://resilience4j.readme.io/ |
| OAuth 2.0 Token Introspection (RFC 7662) | https://datatracker.ietf.org/doc/html/rfc7662 |
