---
name: kubernetes-multi-env-patterns
description: Patterns génériques Kubernetes/Helm pour la gestion multi-environnements (E2E éphémère, TIS/VA/PROD persistants). Architecture des tiers, FQDN cross-namespace, stratégie Helm values par env, Kafka consumer config, SmallRye Config mapping, mount path application.properties.
type: reference
---

# Patterns multi-environnements Kubernetes / Helm

> Patterns génériques extraits d'expériences en grande DSI. Pour la topologie spécifique à votre organisation (cadres d'environnements internes nommés, clusters internes, namespaces, Ingress), voir le repo de souveraineté correspondant.

---

## Architecture des tiers : deux modèles

| Modèle | Usage | Tiers | Namespace |
|--------|-------|-------|-----------|
| **Éphémère** | E2E | Déployés avec l'app, détruits après | `<app>-e2e` |
| **Persistant** | TIS, VA, PROD... | Déployés une fois, partagés | `<app>-dev`, `<app>-preprod`, `<app>-prod` |

### Tiers éphémères (E2E)

Les tiers sont déployés dans le **même namespace** que l'app :
- Accessibles par nom DNS simple (`kafka:9092`, `oracle:1521`, `s3mock:9090`)
- Détruits avec le namespace après les tests
- Isolés des autres environnements (pas d'interférence)

### Tiers persistants (TIS, VA, PROD...)

Les tiers vivent dans un **namespace partagé** du cluster :
- Accessibles par FQDN cross-namespace (`kafka.<app>-dev.svc.cluster.local:9092`)
- Déployés une seule fois, réutilisés par tous les envs du cluster
- En entreprise : infrastructure gérée par l'équipe ops

### FQDN cross-namespace K8s

```
<service>.<namespace>.svc.cluster.local:<port>
```

Exemples :
```
oracle.<app>-dev.svc.cluster.local:1521
kafka.<app>-dev.svc.cluster.local:9092
s3mock.<app>-dev.svc.cluster.local:9090
redis.<app>-dev.svc.cluster.local:6379
```

---

## Stratégie Helm values par environnement

```
helm upgrade --install <release> <chart> \
  -f values-base.yml \        # commun à tous les envs
  -f values-env-<env>.yml     # override par env
```

Le fichier **base** contient :
- Labels, annotations, metadata (équipe, composant, technologie)
- Image par défaut, resources CPU/RAM, probes
- Configuration commune (context root, replicas par défaut)

Le fichier **env** contient :
- Ingress host/path spécifique à l'env
- Connexions aux tiers (Oracle JDBC URL, Kafka brokers, S3 endpoint)
- Variables métier spécifiques (niveau de log, dossier S3, groupe Kafka)

### Convention de nommage des fichiers

```
helm-values/
  <app>-base.yml                  # commun
  <app>-env-e2e.yml               # E2E (éphémère, tiers intra-namespace)
  <app>-env-tis.yml               # TIS (tiers cross-namespace dev)
  <app>-env-va.yml                # VA (tiers cross-namespace preprod)
  <app>-env-prod.yml              # PROD
  <app>-env-<env-explo>.yml       # env d'exploration interne
  <app>-env-pri.yml               # PRI
```

### Différences clés entre E2E et TIS/VA/PROD

| Aspect | E2E | TIS/VA/PROD |
|--------|-----|-------------|
| Tiers DNS | `kafka:9092` (intra-namespace) | `kafka.<app>-dev.svc:9092` (cross-namespace) |
| Oracle | Éphémère dans le namespace | Persistant dans le namespace tiers |
| Kafka `auto.offset.reset` | `earliest` (topics créés à la volée) | `latest` (topics pré-existants) |
| Kafka consumer `group.id` | `e2e-<app>-<canal>` | `tis-<app>-<canal>` (préfixe par env) |
| S3 dossier | `e2e/` | `QL/` (qualif), `PROD/` etc. |
| Replicas | 1 (économie) | 2+ (réalisme) |
| Namespace | Détruit après tests | Persistant |

---

## SmallRye Config — règles de nommage des env vars

Pour les applications Quarkus/SmallRye, les méthodes Java sont converties en env vars :

```
méthode Java        -> propriété kebab-case       -> env var
urlS3()             -> stockageClient.url-s3      -> STOCKAGECLIENT_URL_S3
accessKey()         -> stockageClient.access-key  -> STOCKAGECLIENT_ACCESS_KEY
cheminDossier()     -> stockageClient.chemin-dossier -> STOCKAGECLIENT_CHEMIN_DOSSIER
```

**Règle** : toujours lire le fichier `application.properties` du projet pour connaître les vrais noms de propriétés avant de créer les env vars.

### Mount path application.properties

Le fichier `application.properties` monté en ConfigMap doit correspondre au **WORKDIR du Dockerfile** :

| Format image | WORKDIR | Mount path |
|-------------|---------|------------|
| Quarkus fast-jar | `/app` | `/app/config/application.properties` |
| Quarkus standard runner | `/deployments` | `/deployments/config/application.properties` |
| Spring Boot | `/app` | `/app/config/application.properties` |

---

## Kafka consumer config par environnement

### Consumer groups

Chaque environnement doit avoir un `group.id` unique pour éviter les conflits :

```properties
# E2E
mp.messaging.incoming.reception.group.id=e2e-<app>-reception
# TIS
mp.messaging.incoming.reception.group.id=tis-<app>-reception
# PROD
mp.messaging.incoming.reception.group.id=prod-<app>-reception
```

### `auto.offset.reset` par environnement

| Env | Valeur | Raison |
|-----|--------|--------|
| E2E | `earliest` | Topics créés à la volée par le producteur de test après l'abonnement consumer |
| TIS/VA/PROD | `latest` | Topics pré-existants, pas de replay de messages historiques |

---

## Pièges courants (génériques)

| Piège | Solution |
|-------|----------|
| `application.properties` monté au mauvais path | Vérifier le WORKDIR du Dockerfile (fast-jar = `/app`, standard = `/deployments`) |
| Env var `COMPONENT_URL` au lieu de `COMPONENT_URL_S3` | Lire `application.properties` pour les vrais noms kebab-case |
| Kafka consumer rate les messages en E2E | `auto.offset.reset=earliest` (topics créés après l'abonnement) |
| Namespace inexistant au deploy | Utiliser `helm --create-namespace` |
| Kafka consumer groups en conflit entre envs | Préfixer le `group.id` par l'env (`tis-`, `e2e-`, `prod-`) |
| K8s 1.31 Job status polling | Utiliser `conditions[?(@.type=="Failed")]` pas `conditions[0]` |
| Logs K8s pollués par WARN ConsumerConfig | Les env vars K8s (KAFKA_PORT, etc.) polluent la config Kafka — filtrer dans le log sampling |
