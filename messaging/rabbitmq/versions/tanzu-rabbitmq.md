---
name: tanzu-rabbitmq-versions
description: VMware Tanzu RabbitMQ — versions 2.4.3, 10.0.3, 10.1.2, mapping OSS, fonctionnalités exclusives, chemins d'upgrade, opérateurs Kubernetes
---

# VMware Tanzu RabbitMQ — Versions et spécificités

## Lignes de produit Tanzu RabbitMQ

| Ligne produit | Versions | Cible |
|---|---|---|
| **Tanzu RabbitMQ for TAS** | 2.4.x | Cloud Foundry / Tanzu Application Service |
| **Tanzu RabbitMQ on Cloud Foundry** | 10.0.x, 10.1.x | Cloud Foundry (renommé, version alignée) |
| **Tanzu RabbitMQ on Kubernetes** | 3.13.x, 4.0.x, 4.1.x | Kubernetes (operators + OCI) |

---

## Version 2.4.3 (for Tanzu Application Service)

**Date** : 18 novembre 2025

| Composant | Version |
|---|---|
| RabbitMQ OSS | **3.13.11** |
| Erlang | 26.2.5.16 |
| Stemcell | 1.943 |

### Fonctionnalités clés 2.4.x

- **Warm Standby Replication (WSR)** : réplication continue des définitions de schéma et des messages vers un cluster standby
- **Audit Logger** : journalisation des actions administratives
- **rabbitmqadmin v2** (Rust) : CLI moderne pour l'API HTTP
- **Inter-node TLS** compatible Erlang 26 (corrigé en 2.4.1)

### Problèmes connus

- Federation link restart sur clusters multi-tenants (100+ vhosts) → upgrade bloqué
- ESXi v8.0 avant Update 3 → segfaults Erlang
- Changement de cookie Erlang → redéploiement nécessite downtime

---

## Version 10.0.3 (on Cloud Foundry)

**Date** : 17 juin 2025

| Composant | Version |
|---|---|
| RabbitMQ OSS | **4.0.12** |
| Erlang | 26.2.5.12 |

### CHANGEMENT MAJEUR : 3.13.x → 4.0.x

- **Khepri** (optionnel) : nouveau backend de stockage basé sur Raft (alternative à Mnesia)
- **AMQP 1.0 natif** : intégré nativement (plus besoin de plugin), activé par défaut
- **Quorum queues améliorées** : priorités de messages, consumer priority avec Single Active Consumer, delivery limit par défaut à 20
- **Classic Queue Mirroring SUPPRIMÉ** : les queues mirrored classiques ne bootent plus

### CRITIQUE : blocage d'upgrade

La version 10.0.0 avait un bug critique : `failed_to_deny_deprecated_features, [classic_queue_mirroring]`. Script de contournement requis avant upgrade.

**Prérequis obligatoire** : migrer TOUTES les classic mirrored queues vers quorum queues AVANT l'upgrade de 2.4.x vers 10.0.x.

### WSR : changement de configuration

En 10.0.x, la configuration WSR passe du standby-replication-operator (déprécié) vers le champ `additionalConfig` du CRD `RabbitmqCluster`.

---

## Version 10.1.2 (on Tanzu Platform)

**Date** : 3 mars 2026

| Composant | Version |
|---|---|
| RabbitMQ OSS | **4.1.9** |
| Erlang | **27.3.4.7** |

### CHANGEMENT : Erlang 26.x → 27.x

Saut de version majeure du runtime Erlang.

### Nouvelles fonctionnalités 10.1.x (RabbitMQ 4.1)

- **SNI Routing** : plusieurs instances RabbitMQ sur les mêmes ports externes via hostnames différents
- **AMQP 1.0 over WebSocket** : applications navigateur communicant avec RabbitMQ
- **Authentification x.509** : WSR et Schema Definition Sync supportent les certificats
- **Quorum queues optimisées** : lectures de log déchargées sur les channels → meilleur throughput consumer et utilisation CPU
- **AMQP 1.0 Filter Expressions** : plusieurs clients consommant chacun un sous-ensemble de messages
- **rabbitmqadmin v2** : révision majeure du CLI (Rust)

### BREAKING CHANGES

1. **Classic Queue Mirroring TOTALEMENT SUPPRIMÉ** : le code est entièrement retiré (en 4.0 il était déprécié, en 4.1 il est gone)
2. **APIs de plugins dépréciées supprimées** : plugins custom à mettre à jour
3. **Changements de format de configuration**

---

## Chemins d'upgrade

| De | Vers | RabbitMQ | Erlang | Risque |
|---|---|---|---|---|
| **2.4.3** | **10.0.3** | 3.13.11 → 4.0.12 | 26.2.5.16 → 26.2.5.12 | **ÉLEVÉ** (suppression classic mirroring) |
| **10.0.3** | **10.1.2** | 4.0.12 → 4.1.9 | 26.2.5.12 → 27.3.4.7 | **MOYEN** (Erlang majeur, APIs dépréciées) |
| **2.4.3** | **10.1.2** | 3.13.11 → 4.1.9 | 26.2.5.16 → 27.3.4.7 | **ÉLEVÉ** (passer par 10.0.x obligatoirement) |

### Procédure d'upgrade 2.4.3 → 10.0.3

1. Migrer TOUTES les classic mirrored queues vers quorum queues
2. Appliquer 2.4.4 d'abord (dernière version stable 2.4.x)
3. Sauvegarder les définitions (`rabbitmqctl export_definitions`)
4. Upgrade vers 10.0.1+ (éviter 10.0.0 : bug critique)
5. Vérifier : `rabbitmqctl list_queues name type` → aucune queue `classic` avec mirroring

### Procédure d'upgrade 10.0.3 → 10.1.2

1. Vérifier les plugins custom (APIs dépréciées supprimées)
2. Review des configurations (changements de format)
3. Upgrade vers 10.1.1+ (10.1.0 avait un bug : instances on-demand restant sur 4.0.x)
4. Surveiller le saut Erlang 26 → 27

---

## Fonctionnalités exclusives Tanzu (pas dans l'OSS)

| Feature | Description |
|---|---|
| **Warm Standby Replication (WSR)** | Réplication continue schema + messages vers cluster standby, failover semi-automatique |
| **Schema Definition Sync** | Réplication asynchrone vhosts, users, queues, exchanges, bindings entre clusters |
| **Compression intra-cluster** | Jusqu'à 96% de réduction bande passante (`inet_tcp_compress`). Linux/amd64 uniquement. Mutuellement exclusif avec TLS inter-noeuds |
| **TLS renforcé par défaut** | Variantes TLS non-sûres désactivées, mutual TLS automatique |
| **Intégration HashiCorp Vault** | Auth/authz déléguée à Vault, certificats TLS éphémères via PKI engine |
| **Defaults production-safe** | Runtime Erlang optimisé, crash recovery plus rapide, disque allégé |
| **Support 24/7 VMware avec SLA** | Escalade directe à l'équipe engineering RabbitMQ |

---

## Opérateurs Kubernetes

### Cluster Operator

- **CRD** : `RabbitmqCluster` (API group: `rabbitmq.com/v1beta1`)
- Gère le cycle de vie complet : StatefulSets, ConfigMaps, Services, Secrets
- Champs clés : `replicas`, `image`, `service`, `persistence`, `resources`, `affinity`, `tolerations`, `tls`, `rabbitmq.additionalConfig`, `override`
- `terminationGracePeriodSeconds` : défaut 604800 (7 jours) pour drain sûr des queues

### Messaging Topology Operator

- **CRDs** : Queue, Exchange, Binding, User, Vhost, Policy, Permission, Federation, Shovel, SchemaReplication, SuperStream
- Gère les ressources RabbitMQ déclarativement via K8s manifests

### Matrice versions K8s

| Tanzu RabbitMQ K8s | RabbitMQ OSS | Cluster Operator | Topology Operator |
|---|---|---|---|
| 4.1.10 | 4.1.10 | 2.19.2 | 1.19.0 |
| 4.0.19 | 4.0.19 | 2.19.2 | 1.19.0 |
| 4.0.3 | 4.0.3 | 2.11.0 | 1.15.0 |

---

## Configuration spécifique Tanzu

### WSR (4.0+)

```yaml
# Dans RabbitmqCluster CRD
spec:
  rabbitmq:
    additionalConfig: |
      schema_definition_sync.operating_mode = upstream
```

### Compression intra-cluster

```bash
# Mutuellement exclusif avec TLS inter-noeuds
RABBITMQ_SERVER_START_ARGS="-proto_dist inet_tcp_compress"
```

### TLS-only

```yaml
spec:
  tls:
    secretName: rabbitmq-tls
    caSecretName: rabbitmq-ca
    disableNonTLSListeners: true
```

---

Sources :
- [Tanzu RabbitMQ 2.4 Release Notes](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-rabbitmq-tanzu-platform/2-4/rabbitmq-tp/releases.html)
- [Tanzu RabbitMQ 10.0 Release Notes](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-rabbitmq-tanzu-platform/10-0/rabbitmq-tp/releases.html)
- [Tanzu RabbitMQ 10.1 Release Notes](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-rabbitmq-tanzu-platform/10-1/rabbitmq-tp/releases.html)
- [Warm Standby Replication](https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-rabbitmq-on-kubernetes/4-0/tanzu-rabbitmq-kubernetes/standby-replication.html)
- [Upgrade Error KB (classic queue mirroring)](https://knowledge.broadcom.com/external/article/387844/)
