---
name: kubernetes-gateway-api
description: Kubernetes Gateway API (v1, GA depuis K8s 1.31, 2024) — successeur des Ingress pour exposer du HTTP/HTTPS/L4 sur K8S. CRD Gateway, HTTPRoute, GRPCRoute. Modèle role-oriented (Infra/Cluster Operator vs Application Developer). Implémentations conformes (Istio, Cilium, NGINX, Envoy, Traefik). Statut, migration depuis Ingress, comparaison avec Spring Cloud Gateway.
type: reference
---

# Kubernetes Gateway API

Successeur des Ingress pour exposer du HTTP/HTTPS/L4 sur Kubernetes. **GA depuis K8S 1.31 (août 2024)** pour les CRD `GatewayClass`, `Gateway`, `HTTPRoute`. Spec maintenue par SIG-Network.

> Référence : [gateway-api.sigs.k8s.io](https://gateway-api.sigs.k8s.io/)
> Spec officielle : [GitHub kubernetes-sigs/gateway-api](https://github.com/kubernetes-sigs/gateway-api)

## Pourquoi Gateway API (vs Ingress)

| Aspect | Ingress (legacy) | Gateway API |
|---|---|---|
| Statut | Stable depuis K8S 1.19 — **plus d'évolutions majeures** | GA depuis K8S 1.31 — successeur officiel |
| Expressivité | Limité (basique routing HTTP, dépendances annotations vendor-specific) | Expressif (HTTP, TLS, headers, redirections, mirroring, traffic split, etc.) sans annotations vendor-specific |
| Modèle role-oriented | Mélange responsabilités infra / dev | **3 personas distincts** : Infra provider, Cluster operator, Application developer |
| Portabilité | Annotations vendor-specific → couplage fort | API standardisée, ressources portables entre implémentations |
| Support L4 (TCP, UDP) | Non | Oui (`TCPRoute`, `UDPRoute` — experimental) |
| Cross-namespace routing | Limité | Natif (`ReferenceGrant`) |

⚠️ Ingress n'est **pas déprécié** mais **gelé** : les évolutions vont à Gateway API. Nouveau projet → privilégier Gateway API si l'implémentation cible est conforme.

## Modèle role-oriented

3 personas avec ressources distinctes :

```
Infrastructure provider (cloud provider, hyperviseur)
  └─ GatewayClass (équivalent StorageClass — décrit l'implémentation)

Cluster operator (admin K8S)
  └─ Gateway (instance d'un GatewayClass, écoute sur IPs/ports)

Application developer (équipe SN)
  └─ HTTPRoute / GRPCRoute / TLSRoute (associe un service back à un Gateway)
```

Bénéfice : les développeurs **n'ont plus à se soucier de l'infra** (TLS, hostnames externes, certificats), juste de leurs routes vers leurs services.

## CRD Gateway API

### `GatewayClass`

Décrit l'implémentation (cloud-provider-managed, in-cluster, etc.). Géré par l'**Infrastructure provider**.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: example-cluster-gateway-class
spec:
  controllerName: example.com/gateway-controller
```

### `Gateway`

Instance écoutant le trafic externe. Géré par le **Cluster operator**.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-web
  namespace: gateway-system
spec:
  gatewayClassName: example-cluster-gateway-class
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - name: prod-web-cert
```

### `HTTPRoute`

Routes HTTP attachées au Gateway. Géré par l'**Application developer**.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-team
spec:
  parentRefs:
  - name: prod-web
    namespace: gateway-system
  hostnames:
  - "api.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1/users
    backendRefs:
    - name: users-service
      port: 8080
      weight: 100
  - matches:
    - path:
        type: PathPrefix
        value: /v1/orders
    backendRefs:
    - name: orders-service-v1
      port: 8080
      weight: 90
    - name: orders-service-v2
      port: 8080
      weight: 10   # canary 10%
```

## Fonctionnalités avancées

| Fonctionnalité | Ressource / champ | Note |
|---|---|---|
| Traffic splitting (canary, blue-green) | `backendRefs[].weight` | Pourcentages, plusieurs backends |
| Header-based routing | `matches[].headers` | Match par valeur exact / regex |
| Query-based routing | `matches[].queryParams` | Idem pour query string |
| Redirections | `filters[type=RequestRedirect]` | 301/302 + path/host rewriting |
| URL rewriting | `filters[type=URLRewrite]` | Rewriting de path/host vers le back |
| Request mirroring | `filters[type=RequestMirror]` | Réplique trafic vers un 2e back (testing, shadow) |
| Cross-namespace routes | `ReferenceGrant` | Sécurisé : le ns du Gateway doit accorder l'accès |
| TLS termination | `Gateway.spec.listeners[].tls` | Mode `Terminate` ou `Passthrough` |
| Custom filters | `ExtensionRef` | Plug-in spécifique à l'implémentation (ext_authz Envoy, etc.) |

## Implémentations conformes

(Liste partielle — voir [gateway-api.sigs.k8s.io/implementations/](https://gateway-api.sigs.k8s.io/implementations/) pour le statut détaillé.)

| Implémentation | Statut conformité | Note |
|---|---|---|
| **Istio Gateway** | Conformant | Service mesh complet, basé Envoy |
| **Cilium** | Conformant | eBPF-based, performant |
| **Envoy Gateway** | Conformant | Sponsoring CNCF, géré par la communauté Envoy |
| **NGINX Gateway Fabric** | Conformant | Successeur de NGINX Ingress Controller |
| **Traefik** | Conformant (≥ v3) | Léger, populaire |
| **Kong Ingress Controller** | Conformant | Si on a déjà Kong DataPlane |
| Cloud provider | Variable | GKE Gateway Controller (Conformant), AWS Load Balancer Controller (en cours), Azure Application Gateway |

## Migration depuis Ingress

1. **Vérifier** que l'implémentation Ingress actuelle a une Gateway API conformant counterpart (par ex. NGINX Ingress → NGINX Gateway Fabric)
2. **Installer** les CRD Gateway API (`kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/...`)
3. **Déployer** une `GatewayClass` + `Gateway` correspondant à l'écoute actuelle
4. **Convertir** chaque `Ingress` en `HTTPRoute` (outillage : [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway) — converter officiel)
5. **Tester** en parallèle (les deux peuvent coexister), puis basculer le DNS

⚠️ Les annotations Ingress vendor-specific (`nginx.ingress.kubernetes.io/...`) n'ont **pas** d'équivalent direct — vérifier que la fonctionnalité est couverte par Gateway API ou par `ExtensionRef`.

## Vs Spring Cloud Gateway (et autres API Gateways applicatives)

| Aspect | K8S Gateway API | Spring Cloud Gateway (et similaires) |
|---|---|---|
| Niveau | Infrastructure (K8S CRD) | Applicatif (process Spring) |
| Configuration | YAML K8S déclaratif | YAML Spring + filtres Java custom |
| Filtres custom | Limité à `ExtensionRef` selon l'implémentation | Très extensible (`GatewayFilterFactory` Java) |
| Authent / authz | Délégation (`ExtensionRef ext_authz` typique) | Native (Spring Security, OAuth2) |
| Routing dynamique | Reconfig via kubectl + reconcile controller | Hot-reload depuis discovery (Consul, Eureka, Spring Cloud Config) |
| Coexistence | Possible — Gateway API en edge, SCG en BFF / internal | Idem |

⚠️ **Les deux ne sont pas exclusifs** : architecture courante = Gateway API en edge (TLS, basic routing) + API Gateway applicative (SCG / Kong) en seconde ligne pour authentification, transformation métier, rate limiting fin.

## Statut et adoption (2025)

- GA depuis K8S 1.31 (août 2024) pour `Gateway`, `GatewayClass`, `HTTPRoute`.
- Experimental encore pour `GRPCRoute`, `TCPRoute`, `UDPRoute`, `TLSRoute` (en cours de stabilisation).
- Adoption croissante mais l'**Ingress reste majoritaire** en production en 2025 — Gateway API mature au rythme de la migration.
- À surveiller : Service Mesh Interface (SMI) et Gateway API convergent autour de Gateway API pour les communications est-ouest.

## Anti-patterns

- ❌ Mélanger Ingress et Gateway API sur le même hostname → conflits de routage imprévisibles.
- ❌ Conf complexe dans un seul `HTTPRoute` → préférer plusieurs `HTTPRoute` avec attachement à un `Gateway` partagé (rôle-oriented).
- ❌ Annotations propriétaires sur `HTTPRoute` → casse la portabilité (utiliser `ExtensionRef` officiel).
- ❌ Ignorer `ReferenceGrant` pour les routes cross-namespace → faille de sécurité (n'importe quel ns peut router vers le service d'un autre).

## Ressources

| Source | URL |
|---|---|
| Gateway API — site officiel (SIG-Network) | https://gateway-api.sigs.k8s.io/ |
| GitHub — kubernetes-sigs/gateway-api | https://github.com/kubernetes-sigs/gateway-api |
| Implémentations conformes | https://gateway-api.sigs.k8s.io/implementations/ |
| ingress2gateway (outil de migration) | https://github.com/kubernetes-sigs/ingress2gateway |
| GA announcement K8S 1.31 (août 2024) | https://kubernetes.io/blog/2024/05/09/gateway-api-v1-1/ |
| Comparaison Ingress vs Gateway API | https://gateway-api.sigs.k8s.io/concepts/use-cases/ |
