# Concourse CI — Référence Pipeline

> Référence complète pour l'écriture de pipelines Concourse CI — concepts, steps, resources, patterns, sécurité, intégration.
> Source : documentation officielle concourse-ci.org + retours d'expérience.

---

## 1. Fondamentaux Concourse

### 1.1 Philosophie

Concourse CI est un système de CI/CD **déclaratif** et **hermétique** :

- **Déclaratif** : tout est défini en YAML, versionné en Git
- **Hermétique** : chaque tâche s'exécute dans un container éphémère, sans état partagé
- **Resources-first** : les pipelines sont pilotés par des changements de ressources, pas par des événements
- **Reproductibilité** : pas de plugins opaques, que des containers et des scripts

### 1.2 Concepts clés

| Concept | Définition |
|---------|-----------|
| **Resource** | Source externe versionnée (git, docker-image, S3, etc.) |
| **Resource Type** | Extension définissant comment interagir avec une resource |
| **Job** | Unité d'exécution composée de steps |
| **Step** | Action atomique : `get`, `put`, `task`, `set_pipeline`, `load_var` |
| **Plan** | Séquence ordonnée de steps dans un job |
| **Pipeline** | Ensemble de jobs et resources formant un workflow |
| **Team** | Isolation RBAC entre groupes d'utilisateurs |
| **Worker** | Machine exécutant les containers de tâches |

### 1.3 Pipeline YAML minimal

```yaml
resources:
  - name: source-code
    type: git
    source:
      uri: https://github.com/org/repo
      branch: main

jobs:
  - name: build
    plan:
      - get: source-code
        trigger: true
      - task: compile
        config:
          platform: linux
          image_resource:
            type: registry-image
            source: { repository: maven, tag: "3.9-eclipse-temurin-21" }
          inputs:
            - name: source-code
          run:
            path: /bin/sh
            args: ["-c", "cd source-code && mvn clean package"]
```

---

## 2. Steps avancés

### 2.1 `in_parallel` avec limite

```yaml
- in_parallel:
    limit: 3          # Max 3 steps simultanés
    fail_fast: true    # Arrêter dès le premier échec
    steps:
      - task: test-unit
      - task: test-integration
      - task: lint
      - task: security-scan
```

### 2.2 `across` — Matrice de jobs (Concourse 7+)

```yaml
- task: deploy
  across:
    - var: env
      values: ["dev", "staging", "prod"]
    - var: region
      values: ["eu-west-1", "us-east-1"]
  config:
    params:
      ENV: ((.:env))
      REGION: ((.:region))
```

### 2.3 `set_pipeline: self`

Auto-update du pipeline depuis son propre code :

```yaml
- name: update-pipeline
  plan:
    - get: ci-code
      trigger: true
    - set_pipeline: self
      file: ci-code/pipeline.yml
      var_files:
        - ci-code/vars/common.yml
      vars:
        some_var: some_value
```

### 2.4 `load_var` — Variables dynamiques

```yaml
- load_var: version
  file: source/version.txt      # format: raw (par défaut)

- load_var: config
  file: source/config.yml
  format: yml                   # format: yml → accès ((.:config.key))

- load_var: data
  file: source/data.json
  format: json
  reveal: true                  # afficher la valeur dans les logs
```

### 2.5 `try` — Étape non bloquante

```yaml
- try:
    task: optional-check
    file: ci/tasks/security-scan.yml
```

### 2.6 `ensure` / `on_success` / `on_failure` / `on_abort` / `on_error`

```yaml
- task: deploy
  file: ci/deploy.yml
  on_success:
    put: slack
    params: { text: "Deploy OK ✅" }
  on_failure:
    put: slack
    params: { text: "Deploy FAILED ❌" }
  ensure:
    task: cleanup
    file: ci/cleanup.yml
```

---

## 3. Resources et Resource Types

### 3.1 Types natifs

| Type | Usage |
|------|-------|
| `git` | Clone/push repos Git |
| `registry-image` | Pull/push images OCI |
| `s3` | Upload/download objets S3 |
| `time` | Déclenchement périodique |
| `semver` | Gestion de version sémantique |

### 3.2 Types communautaires utiles

| Type | Usage | Registry |
|------|-------|----------|
| `cf-cli-resource` (cf7) | Déploiement Cloud Foundry | nulldriver/cf-cli-resource |
| `helm3-resource` | Déploiement Helm/K8S | typositoire/concourse-helm3-resource |
| `slack-notification` | Notifications Slack | cfcommunity/slack-notification-resource |
| `concourse-git-semver-tag` | Semver via tags Git | laurentverbruggen/concourse-git-semver-tag-resource |
| `pool-resource` | Locks/mutex entre jobs | concourse/pool-resource |
| `mock-resource` | Tests de pipelines | concourse/mock-resource |

### 3.3 Webhooks

```yaml
resources:
  - name: source
    type: git
    check_every: never           # ← désactiver le polling
    webhook_token: my-secret     # ← activer le webhook
    source:
      uri: git@github.com:org/repo
      branch: main
```

URL du webhook : `https://<concourse>/api/v1/teams/<team>/pipelines/<pipeline>/resources/<resource>/check/webhook?webhook_token=<token>`

### 3.4 `check_every` recommandations

| Scénario | Valeur |
|----------|--------|
| Resource avec webhook | `never` |
| Resource avec semver + webhook | `1h` (compromise) |
| Resource time (cron) | `30s` à `1m` |
| Ressource SNOW/externe | `5m` |
| Resource Helm chart | `24h` |

---

## 4. Tasks

### 4.1 Task inline vs fichier

```yaml
# ✅ Fichier externe (réutilisable, versionné)
- task: build
  file: ci/tasks/build.yml
  params:
    APP_NAME: my-app

# ⚠️ Inline (acceptable pour des one-liners)
- task: version
  config:
    platform: linux
    image_resource:
      type: registry-image
      source: { repository: alpine }
    run:
      path: /bin/sh
      args: ["-c", "date +%Y%m%d%H%M%S > version/timestamp"]
    outputs:
      - name: version
```

### 4.2 Structure d'un fichier task

```yaml
platform: linux

image_resource:
  type: registry-image
  source:
    repository: my-registry/my-build-image
    tag: "1.0.0"

caches:
  - path: .m2/repository    # Cache Maven persiste entre builds

inputs:
  - name: source-code
  - name: pipeline-code

outputs:
  - name: artifacts
  - name: reports

params:
  APP_NAME:             # Requis (vide = obligatoire)
  SKIP_TESTS: "false"   # Avec valeur par défaut

run:
  path: /bin/bash
  args:
    - -euc           # -e: exit on error, -u: undefined var = error, -c: command
    - |
      set -o pipefail
      cd source-code
      mvn clean verify -DskipTests=${SKIP_TESTS}
      cp target/*.jar ../artifacts/
```

### 4.3 `privileged: true`

Nécessaire uniquement pour :
- Construire des images Docker (docker-in-docker)
- Accéder aux devices du worker

**Règle** : ne jamais l'utiliser par défaut, uniquement quand obligatoire.

---

## 5. Variables et Secrets

### 5.1 Types de variables

| Syntaxe | Source | Usage |
|---------|--------|-------|
| `((var))` | var_files, --var, credential manager | Configuration statique |
| `(("path.key"))` | Credential manager (CredHub, Vault) | Secrets |
| `((.:local_var))` | `load_var` dans le même job | Variables dynamiques runtime |
| `((var_source:key.subkey))` | `var_sources` | Constantes globales |

### 5.2 Credential Managers supportés

- **CredHub** (Cloud Foundry) — le plus courant en entreprise
- **HashiCorp Vault** — via secret backend
- **AWS SSM Parameter Store**
- **AWS Secrets Manager**
- **Kubernetes Secrets** (via `conjur` ou autre)

### 5.3 Convention de nommage des secrets

```
/<team>/<pipeline>/<var-name>        # secret par pipeline
/<team>/<var-name>                   # secret partagé par l'équipe
```

---

## 6. Patterns de pipeline avancés

### 6.1 Pipeline instancié (multi-composants)

```bash
fly set-pipeline \
  -p my-platform \
  -c pipeline.yml \
  -l vars/common.yml \
  -l vars/component-a.yml \
  --instance-var component=component-a
```

Un seul YAML, N instances, chacune avec ses variables.

### 6.2 Pipeline fan-in / fan-out

```yaml
jobs:
  - name: build
    plan: [...]
  
  - name: test-unit
    plan:
      - get: artifact
        passed: [build]
        trigger: true
  
  - name: test-integration
    plan:
      - get: artifact
        passed: [build]
        trigger: true
  
  - name: deploy-staging
    plan:
      - get: artifact
        passed: [test-unit, test-integration]  # fan-in
        trigger: true
```

### 6.3 Promotion gate (manual trigger)

```yaml
- name: deploy-prod
  plan:
    - get: artifact
      passed: [deploy-staging]
      # PAS de trigger: true → déclenchement manuel obligatoire
```

### 6.4 Rolling deployment pattern

```yaml
cf-push-rolling: &cf-push-rolling
  put: cf-deploy
  params:
    command: push
    strategy: rolling          # zero-downtime
    app_name: my-app-((env))
    manifest: artifacts/manifest.yml
    staging_timeout: 10        # minutes
    startup_timeout: 10
```

---

## 7. Optimisation et Performance

### 7.1 Réduire le temps de build

1. **Caches** : toujours utiliser `caches:` pour Maven (`.m2`), npm (`node_modules`), pip, etc.
2. **`in_parallel`** : paralléliser les `get` et les tasks indépendantes
3. **Inputs explicites** sur les `put` : `inputs: [only-needed]`
4. **Images légères** : Alpine-based quand possible
5. **Multi-stage builds** : si Docker-in-Docker, utiliser des Dockerfiles multi-stage

### 7.2 Réduire la consommation worker

1. `check_every: never` + webhooks
2. Limiter `in_parallel` avec `limit:`
3. Ne pas utiliser `privileged: true` inutilement
4. Tagger les resource types avec une version fixe
5. Nettoyer les pipelines obsolètes (`fly destroy-pipeline`)

### 7.3 Debugging

```bash
# Exécuter une task en local (sans pipeline)
fly -t team execute -c task.yml -i source-code=./local-source

# Intercepter un container en cours
fly -t team intercept -j pipeline/job -s step-name

# Hijack un container terminé
fly -t team hijack -j pipeline/job -s step-name

# Voir les logs
fly -t team watch -j pipeline/job -b <build-number>

# Valider un pipeline YAML
fly -t team validate-pipeline -c pipeline.yml
```

---

## 8. Sécurité

### 8.1 Règles

- **Ne jamais** hardcoder un secret dans un fichier YAML
- Utiliser `(("credential.key"))` pour tous les secrets
- `reveal: true` sur `load_var` uniquement en debug (jamais en prod)
- Limiter `privileged: true` aux tasks de build Docker
- Rotation régulière des tokens webhook et PATs

### 8.2 RBAC

Concourse supporte les rôles par team :
- **owner** : admin complet
- **member** : set/get pipelines, trigger jobs
- **pipeline-operator** : trigger/pause jobs uniquement
- **viewer** : lecture seule

### 8.3 Audit

```bash
# Lister les pipelines
fly -t team pipelines

# Lister les builds récents
fly -t team builds -c 50

# Voir le statut d'un job
fly -t team jobs -p pipeline-name
```

---

## 9. Anti-patterns

| Anti-pattern | Problème | Solution |
|---|---|---|
| `check_every: 10s` sans webhook | Polling excessif, charge worker | `check_every: never` + webhook |
| `docker-image` resource type | Déprécié, utilise Docker socket | `registry-image` |
| `put` sans `inputs:` explicites | Transfert de tous les volumes | Lister les inputs nécessaires |
| Secrets en clair dans les vars | Fuite de credentials | CredHub / Vault |
| `privileged: true` partout | Risque sécurité | Uniquement pour Docker build |
| Pipeline monolithique 2000+ lignes | Illisible, lent à mettre à jour | Découper par domaine |
| Pas de `serial: true` | Builds concurrents incohérents | `serial: true` sur les deploys |
| Tasks inline complexes | Non réutilisables | Fichiers `.yml` dans `tasks/` |
| Pas de cache Maven/npm | Build lents | `caches: [{ path: .m2 }]` |
| `try:` autour de tout | Masque les erreurs | `try:` uniquement sur les steps optionnels |

---

## 10. Intégration avec l'écosystème

### 11.1 GitLab

```yaml
resources:
  - name: source
    type: git
    source:
      uri: ssh://git@gitlab.example.com:2222/group/project.git
      private_key: (("gitlab.ssh_key"))
      branch: main
```

Webhook GitLab : Settings → Webhooks → URL du webhook Concourse.

### 11.2 Artifactory

Pattern upload :
```yaml
- task: deploy-artifactory
  file: ci/tasks/artifactory/deploy.yml
  params:
    APP_NAME: ((app))
    revision: ((.:version))
```

Pattern download :
```yaml
- task: artifactory-download
  file: ci/tasks/artifactory/download.yml
  params:
    APP_NAME: ((app))
    revision: ((.:version))
```

### 11.3 ServiceNow (SNOW/IAMS)

Resource custom `concourse-snow-resource` pour la gestion des changements :

```yaml
resource_types:
  - name: concourse-snow-resource
    type: docker-image
    source:
      repository: registry/concourse-snow-resource
      tag: 3.1.8

resources:
  - name: changement-snow
    type: concourse-snow-resource
    source:
      SNOW_URL: (("snow.url"))
      SNOW_USER: (("snow.user"))
      SNOW_PASSWORD: (("snow.password"))
      S3_ENDPOINT_URL: (("s3.endpoint"))
      S3_BUCKET: (("s3.bucket"))
      S3_ACCESS_KEY_ID: (("s3.access_key"))
      S3_SECRET_ACCESS_KEY: (("s3.secret_key"))
      FOLDER_PATH: team/changement/app/reference
      WORKFLOW: default_s3
    check_every: 5m
```

---

## 11. Versioning et Conventional Commits

### 12.1 Tagging automatique

```yaml
- task: conventional-commits
  file: ci/tasks/git/conventional-commits.yaml
  output_mapping:
    tag: tags
    changelog: changelog
  params:
    GIT_REPO_URI: ((git-uri))
    GL_TOKEN: (("gitlab.token"))
```

### 12.2 Convention semver

Les tags Git suivent le pattern `MAJOR.MINOR.PATCH` :

```yaml
- name: tag-version
  type: git
  source:
    tag_regex: '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+'
    fetch_tags: true
```

---


---

## 12. Opérations et Incidents

### Restart de l'ATC — ressources bloquées

Après un redémarrage de l'ATC (web), les versions des ressources sont **perdues en mémoire**. Les builds qui attendent des inputs (`get:` avec `passed:` ou `trigger: true`) restent indéfiniment en état "pending" sans message d'erreur clair.

**Diagnostic** : l'API de préparation de build révèle la cause réelle :
```bash
fly -t ci curl /api/v1/builds/{build-id}/preparation
# → "missing_input_reasons": {"my-resource": "latest version of resource not found"}
```

**Résolution** : relancer un check sur les ressources bloquées :
```bash
fly -t ci check-resource -r pipeline/resource-name
# Pour toutes les ressources git après un restart :
for r in source-code config infra; do
  fly -t ci check-resource -r my-pipeline/$r
done
```

Si le check échoue avec "credential not found", le credential manager (K8s/Vault/Conjur) n'a pas le secret correspondant → créer le secret puis re-checker.

### Credential manager K8s — secrets manquants

Avec le credential manager Kubernetes, les secrets se trouvent dans le namespace `concourse-{team}` (ex: `concourse-main`). Un secret manquant bloque les checks de ressource silencieusement.

```bash
# Créer un secret manquant (team-scoped) :
kubectl -n concourse-main create secret generic my-var --from-literal=value="my-value"
# Ou (pipeline-scoped) :
kubectl -n concourse-main create secret generic my-pipeline-my-var --from-literal=value="my-value"
```

Les `-l vars.yml` passés à `fly set-pipeline` n'affectent que l'interpolation au moment du set-pipeline. Les task files sont interpolés au runtime par le credential manager. Si une variable est dans un task file mais pas dans K8s → error à l'exécution.

---

## Journal des mises à jour

| Date | Changement |
|------|-----------|
| 2026-04-05 | Création initiale — référentiel expert Concourse CI basé documentation officielle et best practices |
| 2026-04-20 | Réorganisation — renommé en `pipelines.md`, §9 fly CLI déplacé dans `operations.md`, §12 ops/incidents ajouté |

