# GitOps: Complete Enterprise Reference Guide

## 1. GitOps as a Paradigm Shift

### The 4 OpenGitOps Principles (v1.0.0)

The [OpenGitOps](https://opengitops.dev/) project, a CNCF Sandbox initiative, codified four principles that define what GitOps actually is:

**Principle 1 -- Declarative**
"A system managed by GitOps must have its desired state expressed declaratively." Systems define their target configuration explicitly rather than through imperative commands. You describe *what* the system should look like, not *how* to get there.

**Principle 2 -- Versioned and Immutable**
"Desired state is stored in a way that enforces immutability, versioning and retains a complete version history." Every change has a unique, permanent identifier. You can answer "who changed what, when, and why" for any point in time.

**Principle 3 -- Pulled Automatically**
"Software agents automatically pull the desired state declarations from the source." Deployment tools actively retrieve configuration from repositories. No external system pushes changes into the cluster. The agent inside the cluster initiates all changes.

**Principle 4 -- Continuously Reconciled**
"Software agents continuously observe actual system state and attempt to apply the desired state." The reconciliation loop runs every 3-5 minutes by default, comparing Git commits against live cluster state. When drift occurs, controllers regenerate resources without human intervention.

### Why GitOps Is Fundamentally Different from CI/CD

Traditional CI/CD and GitOps differ at an architectural level -- it is not just a tooling swap:

| Dimension | Traditional CI/CD (Push) | GitOps (Pull) |
|---|---|---|
| **Direction** | CI server pushes to cluster | Agent in cluster pulls from Git |
| **Credentials** | CI needs admin access to every target | Agent needs read-only access to Git |
| **Drift handling** | None -- manual detection | Continuous reconciliation loop |
| **Source of truth** | CI server state / pipeline definitions | Git repository |
| **Blast radius** | CI credential leak = all clusters | Cluster compromise = only that cluster |
| **Rollback** | Re-run old pipeline (if possible) | `git revert` + auto-reconcile |
| **Audit trail** | CI logs (ephemeral) | Git history (permanent) |

The critical insight: in traditional CI/CD, the CI server is God -- it holds credentials for everything and pushes artifacts to targets. In GitOps, the CI server builds and tests artifacts, then writes the result to Git. The cluster-side agent handles deployment. No external system holds cluster credentials.

### What Problems GitOps Solved

1. **Configuration drift** -- Manual `kubectl edit` in production creates invisible divergence. GitOps auto-heals it.
2. **Credential sprawl** -- CI servers with admin keys to 50 clusters. GitOps inverts this: agents only need Git read access.
3. **Audit gaps** -- "Who deployed what?" answered by digging through Jenkins logs. GitOps: `git log`.
4. **Disaster recovery** -- Rebuilding a cluster after failure was a multi-day fire drill. GitOps: bootstrap the agent, point at Git, wait.
5. **Environment inconsistency** -- "It works in staging" because staging was hand-configured differently. GitOps: same source, different overlays.

---

## 2. Architecture Patterns

### Mono-repo vs Multi-repo

**Mono-repo (single repo for all config):**
```
gitops-config/
  apps/
    frontend/
    backend/
    database/
  infrastructure/
    monitoring/
    ingress/
  envs/
    dev/
    staging/
    production/
```
- Pros: Single place to review all changes, atomic cross-service updates, simpler CI
- Cons: Blast radius (one bad merge affects everything), access control is coarse, merge conflicts at scale
- Best for: Small-to-medium teams, <20 services

**Multi-repo (app repo + config repo per team/service):**
```
# Repo: team-alpha-app (source code)
# Repo: team-alpha-config (Kubernetes manifests)
# Repo: platform-config (shared infra)
```
- Pros: Team autonomy, fine-grained permissions, independent release cycles
- Cons: Cross-cutting changes require multi-repo PRs, harder to see the big picture
- Best for: Large organizations, >5 teams, >20 services

**Recommendation**: Separate app code from deployment config. The app repo contains source code. The config repo contains Kubernetes manifests. CI builds the app, updates the image tag in the config repo. GitOps syncs from the config repo.

### Environment Promotion: Folder-based (NOT Branch-based)

Do NOT use Git branches for environments. [This is a well-documented anti-pattern](https://codefresh.io/blog/stop-using-branches-deploying-different-gitops-environments/). Use folders within a single branch:

```
gitops-config/
  base/                          # Shared manifests
    deployment.yaml
    service.yaml
    kustomization.yaml
  overlays/
    dev/
      kustomization.yaml         # Patches for dev
      replicas-patch.yaml
    staging/
      kustomization.yaml         # Patches for staging
    production/
      kustomization.yaml         # Patches for production
      hpa.yaml
      pdb.yaml
```

**Promotion flow with PR gates:**
1. Developer merges feature to `main` -- CI builds image `v1.2.3`
2. CI auto-updates `overlays/dev/kustomization.yaml` with new image tag
3. ArgoCD auto-syncs dev (no approval needed)
4. Automated PR created to update `overlays/staging/` -- requires 1 approval
5. After staging validation, automated PR to update `overlays/production/` -- requires 2 approvals

### Kustomize Overlays vs Helm Values

**Kustomize** -- Patch-based. You write plain YAML, then layer environment-specific patches:

```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml

# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patchesStrategicMerge:
  - replicas-patch.yaml
  - resources-patch.yaml
namespace: production
commonLabels:
  env: production

# overlays/production/replicas-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 5
  template:
    spec:
      containers:
        - name: myapp
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
```

**Helm** -- Template-based. You parameterize everything with Go templates:

```yaml
# values-production.yaml
replicaCount: 5
image:
  repository: myregistry/myapp
  tag: v1.2.3
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
ingress:
  enabled: true
  hosts:
    - myapp.production.example.com
```

**When to use which:**

| Criteria | Kustomize | Helm |
|---|---|---|
| In-house apps with simple config | Excellent | Overkill |
| Third-party software (Prometheus, nginx-ingress) | Poor (rewrite all YAML) | Excellent (use upstream chart) |
| Template reuse across 50+ similar apps | Manual | Chart + values |
| GitOps diff readability | Excellent (plain YAML) | Poor (templates are opaque) |
| Lifecycle management (install/upgrade/rollback) | None (needs ArgoCD/Flux) | Built-in |

**Hybrid approach (recommended for mature teams):** Use Helm to consume upstream charts, then wrap with Kustomize for environment-specific patches:
```yaml
# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
  - name: my-app
    repo: https://charts.example.com
    version: 1.2.3
    releaseName: my-app
    valuesFile: values-production.yaml
```

### ArgoCD vs Flux: Decision Criteria

| Criteria | ArgoCD | Flux |
|---|---|---|
| **UI** | Rich Web UI with diff visualization | No built-in UI (use Weave GitOps) |
| **Multi-cluster** | Hub-and-spoke from single instance | Each cluster runs its own Flux |
| **RBAC** | AppProject + Casbin-based policies | Kubernetes-native RBAC via impersonation |
| **Learning curve** | Higher (more features) | Lower (Kubernetes-native CRDs) |
| **Progressive delivery** | Argo Rollouts (tight integration) | Flagger (separate project) |
| **Notifications** | Built-in (Slack, Teams, webhook) | Notification controller |
| **Multi-tenancy** | AppProject isolation | Kubernetes namespace + RBAC |
| **Helm support** | First-class | First-class via Helm Controller |
| **OCI artifacts** | Supported | First-class support |
| **Community size** | Larger (CNCF Graduated) | Large (CNCF Graduated) |

**Choose ArgoCD when:** You need a UI for developers, manage multiple clusters from a single pane, want integrated progressive delivery with Argo Rollouts.

**Choose Flux when:** You prefer pure Kubernetes-native approach, need strong multi-tenancy via K8s RBAC, run in air-gapped environments, want each cluster fully autonomous.

---

## 3. ArgoCD Deep Dive

### Application CRD: Complete Specification

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-production
  namespace: argocd
  # Finalizers ensure cleanup when Application is deleted
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/part-of: myplatform
    team: backend
  annotations:
    # Notification subscriptions
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: deploys
    notifications.argoproj.io/subscribe.on-sync-failed.slack: alerts
    notifications.argoproj.io/subscribe.on-health-degraded.slack: alerts
spec:
  # Project scoping (RBAC boundary)
  project: production

  # Source configuration
  source:
    repoURL: https://github.com/myorg/gitops-config.git
    targetRevision: main
    path: overlays/production

    # For Helm sources:
    # chart: my-chart
    # helm:
    #   valueFiles:
    #     - values-production.yaml
    #   parameters:
    #     - name: image.tag
    #       value: v1.2.3

    # For Kustomize sources:
    kustomize:
      images:
        - myregistry/myapp:v1.2.3

  # Destination cluster + namespace
  destination:
    server: https://kubernetes.default.svc    # In-cluster
    # OR: server: https://prod-cluster.example.com  # External cluster
    namespace: production

  # Sync policy
  syncPolicy:
    automated:
      prune: true          # Delete resources removed from Git
      selfHeal: true       # Revert manual cluster changes
      allowEmpty: false    # Prevent accidental deletion of all resources
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true     # Prune after all other resources synced
      - ServerSideApply=true
      - Validate=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  # Ignore dynamic fields that cause false OutOfSync
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas       # Managed by HPA
    - group: ""
      kind: Service
      jqPathExpressions:
        - .metadata.annotations["cloud.google.com/neg-status"]
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jqPathExpressions:
        - .webhooks[]?.clientConfig.caBundle
```

### Sync Policies: auto-sync, self-heal, prune

**Auto-sync**: When enabled, ArgoCD automatically applies changes detected in Git. Without it, changes appear as "OutOfSync" and require manual sync.

**Self-heal**: Detects and reverts manual changes made directly to the cluster. If someone runs `kubectl edit` on a resource managed by ArgoCD, self-heal will revert it within 5 seconds (default).

**Prune**: Deletes resources from the cluster that no longer exist in Git. Without prune, removing a YAML file from Git leaves the orphaned resource running in the cluster.

**Production recommendation**: Enable all three but with guardrails:
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - PruneLast=true           # Prune only after everything else succeeds
    - PrunePropagationPolicy=foreground  # Wait for dependents to delete
```

### Sync Waves and Hooks

Sync waves control ordering. Hooks run at specific phases. Combined, they orchestrate complex deployments.

**Phases (in order):**
1. `PreSync` -- Before any resources are applied (database migrations, backups)
2. `Sync` -- Main resource application (deployments, services, configmaps)
3. `PostSync` -- After successful sync (smoke tests, notifications)
4. `SyncFail` -- Only if sync fails (cleanup, alerts)

**Sync wave ordering**: Resources are applied in ascending wave order. Within a wave, they are applied by kind (namespaces before deployments, etc.).

```yaml
# Wave -2: Create namespace and RBAC first
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "-2"

---
# Wave -1: PreSync hook -- Database migration
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "-1"
spec:
  backoffLimit: 1
  activeDeadlineSeconds: 300
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: wait-for-db
          image: busybox:1.36
          command: ['sh', '-c', 'until nc -z postgres-svc 5432; do sleep 2; done']
      containers:
        - name: migrate
          image: myregistry/myapp-migrate:v1.2.3
          command: ["./migrate", "up"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: url

---
# Wave 0: Main deployment (default wave)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myregistry/myapp:v1.2.3

---
# Wave 1: PostSync hook -- Smoke tests
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "1"
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 120
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: smoke
          image: myregistry/smoke-tests:latest
          env:
            - name: TARGET_URL
              value: "http://myapp-svc.production.svc.cluster.local:8080"
          command:
            - /bin/sh
            - -c
            - |
              set -e
              # Health check
              curl -sf $TARGET_URL/health || exit 1
              # Critical endpoint validation
              curl -sf $TARGET_URL/api/v1/status || exit 1
              # Response time check
              RESPONSE_TIME=$(curl -sf -o /dev/null -w '%{time_total}' $TARGET_URL/api/v1/ping)
              echo "Response time: ${RESPONSE_TIME}s"
              # Fail if response > 2 seconds
              echo "$RESPONSE_TIME 2.0" | awk '{if ($1 > $2) exit 1}'

---
# SyncFail hook -- Alert on failure
apiVersion: batch/v1
kind: Job
metadata:
  name: sync-fail-alert
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: alert
          image: curlimages/curl:latest
          command:
            - curl
            - -X POST
            - -H
            - "Content-Type: application/json"
            - -d
            - '{"text":"SYNC FAILED: myapp-production"}'
            - $(SLACK_WEBHOOK_URL)
```

**Hook delete policies:**
- `BeforeHookCreation` -- Delete old hook before creating new one (recommended)
- `HookSucceeded` -- Delete after successful completion
- `HookFailed` -- Delete after failure

### Health Checks

ArgoCD has built-in health checks for standard Kubernetes resources (Deployment, StatefulSet, DaemonSet, Ingress, Service, PVC). For custom resources, define Lua-based health checks:

```yaml
# In argocd-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # Custom health check for CertManager Certificate
  resource.customizations.health.cert-manager.io_Certificate: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" and condition.status == "False" then
            hs.status = "Degraded"
            hs.message = condition.message
            return hs
          end
          if condition.type == "Ready" and condition.status == "True" then
            hs.status = "Healthy"
            hs.message = condition.message
            return hs
          end
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for certificate"
    return hs

  # Custom health check for Argo Rollouts
  resource.customizations.health.argoproj.io_Rollout: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase == "Healthy" then
        hs.status = "Healthy"
        hs.message = "Rollout is healthy"
      elseif obj.status.phase == "Paused" then
        hs.status = "Suspended"
        hs.message = "Rollout is paused"
      elseif obj.status.phase == "Degraded" then
        hs.status = "Degraded"
        hs.message = "Rollout is degraded"
      else
        hs.status = "Progressing"
        hs.message = "Rollout is progressing"
      end
    end
    return hs
```

### App-of-Apps Pattern

A root Application manages child Applications. Each child Application is a YAML file in a Git directory:

```yaml
# root-app.yaml -- The parent that manages everything
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/gitops-config.git
    targetRevision: main
    path: apps/              # Directory containing child Application YAMLs
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```yaml
# apps/frontend.yaml -- Child application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: frontend
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: production
  source:
    repoURL: https://github.com/myorg/gitops-config.git
    targetRevision: main
    path: services/frontend/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: frontend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### ApplicationSet for Dynamic Environments

ApplicationSet generates Applications automatically from templates:

```yaml
# Generate one Application per cluster per app
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-cluster-apps
  namespace: argocd
spec:
  generators:
    # Matrix: for each cluster x each app
    - matrix:
        generators:
          - clusters:
              selector:
                matchLabels:
                  env: production
          - git:
              repoURL: https://github.com/myorg/gitops-config.git
              revision: main
              directories:
                - path: services/*
  template:
    metadata:
      name: '{{path.basename}}-{{name}}'
    spec:
      project: production
      source:
        repoURL: https://github.com/myorg/gitops-config.git
        targetRevision: main
        path: '{{path}}/overlays/{{metadata.labels.env}}'
      destination:
        server: '{{server}}'
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true

---
# Generate preview environments from open PRs
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: preview-envs
  namespace: argocd
spec:
  generators:
    - pullRequest:
        github:
          owner: myorg
          repo: myapp
          labels:
            - preview
        requeueAfterSeconds: 60
  template:
    metadata:
      name: 'preview-{{number}}'
    spec:
      project: previews
      source:
        repoURL: https://github.com/myorg/myapp.git
        targetRevision: '{{head_sha}}'
        path: k8s/preview
      destination:
        server: https://kubernetes.default.svc
        namespace: 'preview-{{number}}'
      syncPolicy:
        automated:
          prune: true
        syncOptions:
          - CreateNamespace=true
```

### Multi-cluster Management

Register external clusters:
```bash
# Via CLI (creates service account argocd-manager on target cluster)
argocd cluster add my-prod-context --name prod-cluster-eu

# Via declarative Secret (GitOps-native)
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: prod-cluster-eu
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    env: production
    region: eu-west-1
type: Opaque
stringData:
  name: prod-cluster-eu
  server: https://prod-eu.example.com:6443
  config: |
    {
      "bearerToken": "<service-account-token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64-ca-cert>"
      }
    }
```

Scaling considerations: Beyond 15-20 clusters, enable controller sharding and Redis HA.

### RBAC with AppProject

```yaml
# AppProject: Restrict what teams can deploy
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-backend
  namespace: argocd
spec:
  description: Backend team project
  # Only allow sources from team's repos
  sourceRepos:
    - https://github.com/myorg/backend-*
    - https://charts.example.com

  # Only allow deploying to specific namespaces
  destinations:
    - server: https://kubernetes.default.svc
      namespace: backend-*
    - server: https://prod-cluster.example.com
      namespace: backend-*

  # Restrict which K8s resources can be deployed
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
  namespaceResourceWhitelist:
    - group: 'apps'
      kind: Deployment
    - group: ''
      kind: Service
    - group: ''
      kind: ConfigMap
    - group: networking.k8s.io
      kind: Ingress

  # Block dangerous resources
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota

  # Project-scoped roles (bound to SSO groups)
  roles:
    - name: developer
      description: Read-only + sync
      policies:
        - p, proj:team-backend:developer, applications, get, team-backend/*, allow
        - p, proj:team-backend:developer, applications, sync, team-backend/*, allow
      groups:
        - backend-developers    # SSO/OIDC group

    - name: admin
      description: Full access within project
      policies:
        - p, proj:team-backend:admin, applications, *, team-backend/*, allow
      groups:
        - backend-leads
```

Global RBAC in `argocd-rbac-cm`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    # Platform team gets admin
    g, platform-engineers, role:admin

    # Backend team scoped to their project
    p, role:backend-dev, applications, get, team-backend/*, allow
    p, role:backend-dev, applications, sync, team-backend/*, allow
    p, role:backend-dev, applications, action/*, team-backend/*, allow
    p, role:backend-dev, logs, get, team-backend/*, allow
    g, backend-developers, role:backend-dev

    # Read-only for everyone else
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, logs, get, */*, deny
```

### Notifications

```yaml
# argocd-notifications-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  # Slack service configuration
  service.slack: |
    token: $slack-token

  # Microsoft Teams via webhook
  service.teams: |
    recipientUrls:
      deployments: $teams-webhook-url

  # Custom webhook
  service.webhook.grafana: |
    url: https://grafana.example.com/api/annotations
    headers:
      - name: Authorization
        value: Bearer $grafana-token
      - name: Content-Type
        value: application/json

  # Trigger definitions
  trigger.on-deployed: |
    - description: Application synced and healthy
      send:
        - app-deployed
      when: app.status.operationState.phase in ['Succeeded'] and
            app.status.health.status == 'Healthy'

  trigger.on-health-degraded: |
    - description: Application health degraded
      send:
        - app-degraded
      when: app.status.health.status == 'Degraded'

  # Message templates
  template.app-deployed: |
    slack:
      attachments: |
        [{
          "color": "#18be52",
          "title": "{{.app.metadata.name}} deployed",
          "fields": [
            {"title": "Revision", "value": "{{.app.status.sync.revision | trunc 7}}", "short": true},
            {"title": "Cluster", "value": "{{.app.spec.destination.server}}", "short": true}
          ]
        }]
    teams:
      title: "Deployment: {{.app.metadata.name}}"

  template.app-degraded: |
    slack:
      attachments: |
        [{
          "color": "#f4c030",
          "title": ":warning: {{.app.metadata.name}} DEGRADED",
          "text": "Health: {{.app.status.health.status}}\nMessage: {{.app.status.health.message}}"
        }]

---
# Secret for tokens
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
type: Opaque
stringData:
  slack-token: xoxb-your-bot-token
  teams-webhook-url: https://outlook.office.com/webhook/xxx
  grafana-token: your-grafana-api-key
```

Subscribe applications via annotations:
```yaml
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: deploys-channel
    notifications.argoproj.io/subscribe.on-health-degraded.slack: alerts-channel
    notifications.argoproj.io/subscribe.on-deployed.teams: deployments
```

### Diff Customization (ignoreDifferences)

Common fields to ignore:
```yaml
spec:
  ignoreDifferences:
    # HPA manages replicas -- don't flag as drift
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas

    # Admission webhooks inject caBundle
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jqPathExpressions:
        - .webhooks[]?.clientConfig.caBundle

    # GKE adds annotations to Services
    - group: ""
      kind: Service
      jsonPointers:
        - /metadata/annotations/cloud.google.com~1neg-status

    # Controller-managed fields
    - group: apps
      kind: Deployment
      managedFieldsManagers:
        - kube-controller-manager
```

System-level (for all apps) in `argocd-cm`:
```yaml
data:
  resource.customizations.ignoreDifferences.all: |
    managedFieldsManagers:
      - kube-controller-manager
      - kube-scheduler
```

### ArgoCD Image Updater

Automatically updates container image tags without manual Git commits:

```yaml
# Application with Image Updater annotations
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
  annotations:
    # Track this image
    argocd-image-updater.argoproj.io/image-list: myapp=myregistry/myapp
    # Use semver strategy (update to latest semver-compatible tag)
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver
    # Only consider tags matching this constraint
    argocd-image-updater.argoproj.io/myapp.semver-constraint: "~1.2"
    # Write changes back to Git (not just override in ArgoCD)
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/write-back-target: kustomization
    argocd-image-updater.argoproj.io/git-branch: main
spec:
  # ... standard Application spec
```

Update strategies:
- `semver` -- Picks the highest semver-compatible tag (recommended)
- `latest` -- Picks the most recently built image
- `digest` -- Updates to the latest digest of a fixed tag
- `name` -- Alphabetical sort

---

## 4. Rollback Procedures

### Method 1: Git Revert (Recommended -- Preserves GitOps Purity)

```bash
# Identify the bad commit
git log --oneline -10

# Revert it (creates a NEW commit -- history moves forward)
git revert abc1234 --no-edit

# Push -- ArgoCD auto-reconciles
git push origin main
```

**Why `git revert` and never `git reset --hard`**: Revert creates a new commit. The history shows what happened and why it was undone. Reset destroys history. In a team environment, reset causes chaos.

### Method 2: ArgoCD History (Quick, but Temporary)

```bash
# List sync history
argocd app history myapp-production

# Rollback to a specific revision
argocd app rollback myapp-production 3

# WARNING: If auto-sync is enabled, ArgoCD will show the app as "OutOfSync"
# because the live state no longer matches Git HEAD.
# You MUST follow up with a git revert to make the rollback permanent.
```

Via the ArgoCD UI: Application > History and Rollback > Select revision > Rollback.

### Method 3: ArgoCD API (for automation)

```bash
# Sync to a specific Git revision (not HEAD)
argocd app sync myapp-production --revision abc1234

# Or via REST API
curl -X POST https://argocd.example.com/api/v1/applications/myapp-production/sync \
  -H "Authorization: Bearer $ARGOCD_TOKEN" \
  -d '{"revision": "abc1234"}'
```

### Flux Rollback Procedure

```bash
# 1. Suspend reconciliation to prevent Flux from fighting your rollback
flux suspend kustomization myapp-production

# 2. Revert in Git
git revert abc1234 --no-edit
git push origin main

# 3. Resume reconciliation
flux resume kustomization myapp-production
```

### Database Migration Rollback

This is the hardest problem in GitOps rollback. Considerations:

1. **Forward-only migrations**: Design migrations to be backward-compatible. The new schema should work with both old and new application code. This is the only safe approach at scale.

2. **Rollback scripts**: Pair every `up` migration with a `down` migration. The `SyncFail` hook can trigger the down migration:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-rollback
  annotations:
    argocd.argoproj.io/hook: SyncFail
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: rollback
          image: myregistry/myapp-migrate:v1.2.3
          command: ["./migrate", "down", "1"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: url
```

3. **Expand-and-contract pattern** (recommended for production):
   - Deploy v1.1: Add new column (nullable), keep old column
   - Deploy v1.2: Backfill new column, application writes to both
   - Deploy v1.3: Application reads from new column only
   - Deploy v1.4: Drop old column

### Stateful Application Rollback

- **PVCs**: Kubernetes PVCs survive pod restarts and rollbacks. A Deployment rollback does not affect persistent data.
- **StatefulSets**: Rolling back a StatefulSet image is safe; data on PVCs remains. But if the new version modified on-disk format, rollback may require data migration.
- **Databases (Operators)**: Do NOT blindly rollback a database operator version. Operator upgrades may have changed CRD schemas or data formats. Always check operator release notes for rollback compatibility.

### Emergency: When Git Is Unavailable

If Git is down and you need an emergency fix:

```bash
# 1. Disable auto-sync on the affected application
argocd app set myapp-production --sync-policy none

# 2. Apply the emergency fix directly
kubectl apply -f emergency-fix.yaml -n production

# 3. Document what you did and why
# 4. IMMEDIATELY after Git is back: commit the fix to Git
# 5. Re-enable auto-sync
argocd app set myapp-production --sync-policy automated --self-heal --auto-prune
```

This is an absolute last resort. Every direct `kubectl apply` breaks the GitOps contract. The reconciliation loop WILL revert your change once auto-sync is re-enabled unless you committed it to Git.

---

## 5. Testing in GitOps

### Pre-deployment Validation (CI Pipeline -- Before Merge)

Run these tools in CI before any PR is merged:

```yaml
# .github/workflows/validate-manifests.yaml
name: Validate Kubernetes Manifests
on:
  pull_request:
    paths: ['overlays/**', 'base/**']

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      # Build manifests from Kustomize
      - name: Build manifests
        run: kustomize build overlays/production > /tmp/manifests.yaml

      # Schema validation against target K8s version
      - name: Kubeval
        run: |
          kubeval /tmp/manifests.yaml \
            --kubernetes-version 1.29.0 \
            --strict

      # Best-practice scoring
      - name: Kube-score
        run: |
          kube-score score /tmp/manifests.yaml \
            --output-format ci

      # Policy enforcement with OPA
      - name: Conftest
        run: |
          conftest test /tmp/manifests.yaml \
            --policy policies/ \
            --output table

      # Detect deprecated APIs
      - name: Pluto
        run: |
          pluto detect-files -d /tmp/manifests.yaml \
            --target-versions k8s=v1.29.0
```

Example Conftest/OPA policies:
```rego
# policies/deployment.rego
package main

deny[msg] {
  input.kind == "Deployment"
  not input.spec.template.spec.containers[_].resources.limits
  msg := sprintf("Deployment %s must have resource limits", [input.metadata.name])
}

deny[msg] {
  input.kind == "Deployment"
  input.spec.template.spec.containers[_].image
  endswith(input.spec.template.spec.containers[_].image, ":latest")
  msg := sprintf("Deployment %s must not use :latest tag", [input.metadata.name])
}

deny[msg] {
  input.kind == "Deployment"
  not input.spec.template.spec.securityContext.runAsNonRoot
  msg := sprintf("Deployment %s must set runAsNonRoot", [input.metadata.name])
}
```

### Post-deployment Smoke Tests (PostSync Hook)

Already shown in Section 3 (sync waves). The key design principles:

1. **Fast**: Smoke tests should complete in under 2 minutes
2. **Focused**: Test critical paths only (health endpoint, auth, main business flow)
3. **Idempotent**: Safe to run multiple times
4. **Actionable**: Failure message should tell you what broke

### Progressive Delivery with Argo Rollouts

#### Canary with Automated Analysis

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  replicas: 10
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myregistry/myapp:v1.2.3
          ports:
            - containerPort: 8080
  strategy:
    canary:
      canaryService: myapp-canary
      stableService: myapp-stable
      trafficRouting:
        istio:
          virtualServices:
            - name: myapp-vsvc
              routes:
                - primary
        # OR nginx:
        #   stableIngress: myapp-ingress
      steps:
        # Phase 1: 5% traffic, run analysis for 5 minutes
        - setWeight: 5
        - analysis:
            templates:
              - templateName: success-rate
              - templateName: latency-check
            args:
              - name: service-name
                value: myapp-canary.production.svc.cluster.local
        - pause: { duration: 5m }

        # Phase 2: 25% traffic
        - setWeight: 25
        - pause: { duration: 5m }

        # Phase 3: 50% traffic, another analysis round
        - setWeight: 50
        - analysis:
            templates:
              - templateName: success-rate
            args:
              - name: service-name
                value: myapp-canary.production.svc.cluster.local
        - pause: { duration: 10m }

        # Phase 4: 100% -- full promotion
        - setWeight: 100

---
# AnalysisTemplate: Prometheus success rate
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  args:
    - name: service-name
  metrics:
    - name: success-rate
      interval: 60s
      count: 5
      successCondition: result[0] >= 0.95
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus.monitoring.svc.cluster.local:9090
          query: |
            sum(rate(
              http_requests_total{
                service="{{args.service-name}}",
                status=~"2.*"
              }[2m]
            )) /
            sum(rate(
              http_requests_total{
                service="{{args.service-name}}"
              }[2m]
            ))

---
# AnalysisTemplate: P99 latency check
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: latency-check
spec:
  args:
    - name: service-name
  metrics:
    - name: p99-latency
      interval: 60s
      count: 5
      successCondition: result[0] < 500
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus.monitoring.svc.cluster.local:9090
          query: |
            histogram_quantile(0.99,
              sum(rate(
                http_request_duration_milliseconds_bucket{
                  service="{{args.service-name}}"
                }[2m]
              )) by (le)
            )
```

If the analysis fails (success rate drops below 95% or P99 latency exceeds 500ms), Argo Rollouts automatically aborts the rollout and scales back to the stable version.

#### Blue-Green with Pre/Post Promotion Analysis

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp-bluegreen
spec:
  replicas: 5
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myregistry/myapp:v1.2.3
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
  strategy:
    blueGreen:
      activeService: myapp-active
      previewService: myapp-preview
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 60

      # Run analysis BEFORE switching traffic
      prePromotionAnalysis:
        templates:
          - templateName: smoke-test-job
        args:
          - name: preview-url
            value: http://myapp-preview.production.svc.cluster.local:8080

      # Run analysis AFTER switching traffic
      postPromotionAnalysis:
        templates:
          - templateName: success-rate
        args:
          - name: service-name
            value: myapp-active.production.svc.cluster.local

---
# AnalysisTemplate: Run a smoke test Job
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: smoke-test-job
spec:
  args:
    - name: preview-url
  metrics:
    - name: smoke-test
      count: 1
      provider:
        job:
          spec:
            backoffLimit: 0
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: smoke
                    image: myregistry/smoke-tests:latest
                    env:
                      - name: TARGET_URL
                        value: "{{args.preview-url}}"
                    command:
                      - /bin/sh
                      - -c
                      - |
                        set -e
                        curl -sf $TARGET_URL/health
                        curl -sf $TARGET_URL/api/v1/status
                        echo "Smoke tests passed"
```

---

## 6. Business Applications

### Feature Flags Integration

Store feature flag configuration in Git alongside your deployment manifests:

```yaml
# overlays/production/feature-flags.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags
  namespace: production
data:
  flags.yaml: |
    new-checkout-flow:
      enabled: false
      rollout-percentage: 0
    dark-mode:
      enabled: true
      rollout-percentage: 100
    beta-analytics:
      enabled: true
      rollout-percentage: 25
      allowed-users:
        - user-a@example.com
        - user-b@example.com
```

Or use a Git-native feature flag tool like Flipt, which stores all flags directly in Git repositories as YAML, enabling version control, branching, and GitOps integration natively.

### Database Schema Management

**SchemaHero** -- A Kubernetes operator for declarative database schema management (GitOps for database schemas):

```yaml
apiVersion: databases.schemahero.io/v1alpha4
kind: Database
metadata:
  name: myapp-db
spec:
  connection:
    postgres:
      uri:
        valueFrom:
          secretKeyRef:
            name: db-credentials
            key: uri

---
apiVersion: schemas.schemahero.io/v1alpha4
kind: Table
metadata:
  name: users
spec:
  database: myapp-db
  name: users
  schema:
    postgres:
      primaryKey: [id]
      columns:
        - name: id
          type: uuid
          default: uuid_generate_v4()
        - name: email
          type: varchar(255)
          constraints:
            notNull: true
        - name: created_at
          type: timestamptz
          default: now()
      indexes:
        - columns: [email]
          isUnique: true
```

**Atlas Kubernetes Operator** -- Brings the GitOps paradigm to database migrations via CRDs that define and apply schema changes declaratively.

### Secrets Management

#### Sealed Secrets (Simple, Git-centric)

```bash
# Encrypt a secret using the cluster's public key
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
```

```yaml
# sealed-secret.yaml -- Safe to commit to Git
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  encryptedData:
    password: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
    username: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
  template:
    metadata:
      name: db-credentials
      namespace: production
    type: Opaque
```

Limitation: Each cluster has its own key-pair. Does not scale well beyond a single cluster.

#### External Secrets Operator (Recommended for Production)

```yaml
# ClusterSecretStore: Connect to Vault (cluster-wide)
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: https://vault.example.com
      path: secret
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: external-secrets
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets

---
# ExternalSecret: Sync a specific secret from Vault
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1h     # Auto-rotate every hour
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: production/database
        property: username
    - secretKey: password
      remoteRef:
        key: production/database
        property: password
```

#### SOPS with Flux (Encrypted files in Git, decrypted on cluster)

```yaml
# .sops.yaml -- Encryption rules
creation_rules:
  - path_regex: .*\.enc\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

#### Decision Matrix

| Approach | Scale | Complexity | Rotation | Multi-cluster |
|---|---|---|---|---|
| Sealed Secrets | 1 cluster, <50 secrets | Low | Manual | Poor |
| SOPS + age/KMS | Small teams | Medium | Manual + Git commit | Medium |
| External Secrets + Vault | Enterprise | High (initial) | Automatic | Excellent |
| CSI Secrets Driver | Azure/AWS native | Medium | Automatic | Good |

### Compliance and Audit Trail

Git history IS your audit log:

```bash
# Who deployed what to production and when?
git log --oneline --format="%h %ai %an: %s" -- overlays/production/

# What changed in the last production deployment?
git diff HEAD~1 -- overlays/production/

# Full blame for any configuration
git blame overlays/production/kustomization.yaml
```

For regulated industries, combine with:
- **Signed commits** (`git commit -S`) for non-repudiation
- **Branch protection rules** requiring PR approval
- **CODEOWNERS** files for mandatory reviewers per directory
- **PR templates** with compliance checklists

---

## 7. Operational Excellence

### Drift Detection and Remediation

ArgoCD's reconciliation loop handles drift automatically when `selfHeal: true`. But you should also monitor drift:

```yaml
# Prometheus alerts for drift
groups:
  - name: argocd-drift
    rules:
      - alert: ArgoCD_ApplicationOutOfSync
        expr: |
          argocd_app_info{sync_status="OutOfSync"} == 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.name }} has been out of sync for 10 minutes"

      - alert: ArgoCD_ApplicationDegraded
        expr: |
          argocd_app_info{health_status="Degraded"} == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.name }} health is degraded"

      - alert: ArgoCD_SyncFailed
        expr: |
          increase(argocd_app_sync_total{phase="Failed"}[1h]) > 0
        labels:
          severity: critical
        annotations:
          summary: "Sync failed for {{ $labels.name }}"
```

Use admission controllers (Kyverno) to block manual changes:
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-manual-changes
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: block-non-gitops-changes
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - Service
                - ConfigMap
              namespaces:
                - production
      exclude:
        any:
          - subjects:
              - kind: ServiceAccount
                name: argocd-application-controller
                namespace: argocd
      validate:
        message: "Direct changes to production resources are blocked. Use GitOps."
        deny: {}
```

### Disaster Recovery: Rebuild Cluster from Git

This is GitOps's killer feature. If a cluster is destroyed, recovery is a deterministic process:

```bash
# 1. Provision new cluster (Terraform/Pulumi/ClusterAPI)
terraform apply -target=module.k8s_cluster

# 2. Bootstrap ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Apply the root application (app-of-apps)
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/gitops-config.git
    targetRevision: main
    path: clusters/production
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# 4. ArgoCD reconciles EVERYTHING from Git:
#    - Namespaces, RBAC, NetworkPolicies
#    - All Applications (app-of-apps)
#    - All workloads, services, ingresses
#    - External Secrets Operator syncs secrets from Vault
#    - CertManager reissues certificates
```

What GitOps CANNOT restore:
- **Persistent data** (PVC contents, databases) -- Use Velero or cloud-native backup
- **External state** (DNS records, load balancer IPs) -- Use ExternalDNS + GitOps
- **In-flight transactions** -- Application-level concern

Target: A cluster that can rebuild itself from Git in under 1 hour.

### Observability of the GitOps Pipeline

Monitor the GitOps controllers themselves:

```yaml
# Grafana dashboard queries for ArgoCD health
# Sync success rate
sum(rate(argocd_app_sync_total{phase="Succeeded"}[1h])) /
sum(rate(argocd_app_sync_total[1h])) * 100

# Average sync duration
avg(argocd_app_sync_duration_seconds) by (name)

# Number of applications per health status
count(argocd_app_info) by (health_status)

# Reconciliation queue depth
argocd_app_reconcile_count
```

Key metrics to track:
- **Sync success rate** (target: >99%)
- **Mean time to sync** (time from Git push to cluster state change)
- **Drift events per week** (manual changes detected)
- **Failed syncs per day** (broken manifests / dependency issues)
- **Rollback frequency** (indicator of release quality)

### Common Failure Modes

| Failure | Symptom | Resolution |
|---|---|---|
| Out of sync, can't sync | Resources stuck in "Progressing" | Check resource health, events, pod logs |
| Sync succeeds but app unhealthy | Health check shows "Degraded" | Check readiness probes, dependencies |
| Infinite sync loop | Sync counter increasing rapidly | Check `ignoreDifferences` -- a controller is mutating a field ArgoCD keeps trying to revert |
| PreSync hook timeout | Sync stuck in "PreSync" phase | Check Job logs, increase `activeDeadlineSeconds` |
| Repository access denied | "permission denied" in ArgoCD logs | Rotate SSH key / token, check repo URL |
| Cluster unreachable | Applications show "Unknown" health | Check network connectivity, cluster credentials |
| Out of memory on ArgoCD | Controller OOMKilled | Increase resources, enable sharding for large installations |

---

## 8. Anti-patterns

### 1. Direct `kubectl apply` in Production

**The violation**: Running `kubectl edit deployment/myapp -n production` or `kubectl apply -f hotfix.yaml` directly.

**Why it's deadly**: Self-heal will revert the change within seconds if enabled. If self-heal is off, you now have invisible drift. Nobody knows the cluster state differs from Git.

**The contract**: If it is not in Git, it does not exist. No exceptions. If you need an emergency fix, commit to Git first. If Git is down, disable auto-sync, apply the fix, and commit immediately when Git is back.

### 2. Storing Secrets in Git

Even "encrypted" secrets have tradeoffs:

- **Plaintext secrets**: Never. Ever.
- **Base64-encoded secrets** (standard K8s Secret YAML): Base64 is encoding, not encryption. This is plaintext with extra steps.
- **Sealed Secrets**: Acceptable for small scale. But the encrypted blob in Git is still a target -- if the cluster private key leaks, all historical secrets are compromised.
- **SOPS-encrypted**: Better. Key management is external (KMS/age). But rotation requires re-encrypting and committing.
- **Recommendation**: Use External Secrets Operator. Git only contains references to Vault/AWS Secrets Manager paths. The actual secret values never touch Git.

### 3. Branch-based Environments

**The anti-pattern**: `main` branch = production, `staging` branch = staging, `develop` branch = dev.

**Why it fails**:
- Cherry-picking between branches creates drift between environments
- Merge conflicts are constant and painful
- You cannot easily answer "what is the diff between staging and production?"
- Promotion is a merge operation, mixing code history with deployment state

**The fix**: Single branch, folder-based environments (see Section 2).

### 4. CIOps Disguised as GitOps

**The anti-pattern**: CI pipeline runs `kubectl apply` or `helm upgrade` after building. The CI server holds cluster credentials and pushes changes.

**Why it's not GitOps**: Violates Principle 3 (Pulled Automatically). The CI server is the deployment authority. If CI is down, you cannot deploy. If CI credentials leak, all clusters are compromised.

**The fix**: CI builds artifacts and updates image tags in the GitOps repo. A cluster-side agent (ArgoCD/Flux) pulls and applies.

### 5. Mixing Imperative and Declarative

**The anti-pattern**: Some resources managed by ArgoCD, some by Helm CLI, some by Terraform, some by manual `kubectl`. Nobody knows which system manages what.

**The fix**: One system of record per resource. Label everything. Use ArgoCD's resource tracking to know what it manages. If Terraform manages infrastructure (VPCs, node pools), ArgoCD manages everything inside the cluster.

### 6. Using the ArgoCD UI to Create Applications

**The anti-pattern**: Clicking "New App" in the ArgoCD UI for production applications.

**Why it's dangerous**: That Application exists only in ArgoCD's internal state. If ArgoCD's storage is lost, the Application definition is gone. There is no Git record.

**The fix**: Every Application is a YAML file in Git, managed by an app-of-apps or ApplicationSet. The UI "New App" button is for experiments only.

### 7. Mutable Image Tags

**The anti-pattern**: Using `image: myapp:latest` or `image: myapp:staging` in production manifests.

**Why it breaks GitOps**: Git shows the same tag across multiple commits, but the actual image content changed. You cannot determine what is running. Rollback to a previous commit pulls a different image than what was originally deployed.

**The fix**: Always use immutable references:
- Semantic version tags: `myapp:v1.2.3`
- SHA digests: `myapp@sha256:abc123def456...`

### 8. Too Many Manual Approvals

**The anti-pattern**: Every sync requires manual approval. Production auto-sync is permanently disabled. Changes queue up.

**Why it's problematic**: Blocks the reconciliation loop. Drift accumulates. Developers batch changes to avoid the approval overhead, making each deployment riskier.

**The balanced approach**: Auto-sync for dev/staging. For production, use auto-sync with `selfHeal: true` but require PR approval to merge to the production overlay. The approval happens at the Git level, not the sync level.

---

## Sources

- [OpenGitOps Principles](https://opengitops.dev/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/en/stable/)
- [Flux Documentation](https://fluxcd.io/docs/)
- [Argo Rollouts](https://argoproj.github.io/rollouts/)
- [GitOps Architecture Patterns and Anti-Patterns](https://platformengineering.org/blog/gitops-architecture-patterns-and-anti-patterns)
- [ArgoCD Sync Waves and Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ArgoCD RBAC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [ArgoCD Notifications](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/)
- [ArgoCD Image Updater](https://argocd-image-updater.readthedocs.io/)
- [How to Model GitOps Environments](https://codefresh.io/blog/how-to-model-your-gitops-environments-and-promote-releases-between-them/)
- [Stop Using Branches for GitOps Environments](https://codefresh.io/blog/stop-using-branches-deploying-different-gitops-environments/)
- [Engineering Fundamentals: GitOps Secret Management](https://microsoft.github.io/code-with-engineering-playbook/CI-CD/gitops/secret-management/)
- [GitOps Secrets with ArgoCD, Vault, and ESO](https://codefresh.io/blog/gitops-secrets-with-argo-cd-hashicorp-vault-and-the-external-secret-operator/)
- [Automated Deployment Rollbacks with GitOps](https://medium.com/@bavicnative/automating-deployment-rollbacks-with-gitops-3887a81e1b2a)
- [ArgoCD Rollback Guide](https://thedevopstooling.com/argocd-rollback-deployment/)
- [The Hard Truth about GitOps and Database Rollbacks](https://atlasgo.io/blog/2024/11/14/the-hard-truth-about-gitops-and-db-rollbacks)
- [GitOps in 2025 - CNCF](https://www.cncf.io/blog/2025/06/09/gitops-in-2025-from-old-school-updates-to-the-modern-way/)
- [Blue/Green and Canary with Argo Rollouts](https://www.redhat.com/en/blog/blue-green-canary-argo-rollouts)
- [Progressive Delivery Pipeline Design](https://dstw.github.io/2025/06/01/progressive-delivery-pipeline/)
- [Disaster Recovery with GitOps](https://www.redhat.com/en/blog/disaster-recovery-with-gitops)
- [Kustomize vs Helm 2026](https://sanj.dev/post/kustomize-vs-helm-2026)
- [ArgoCD Anti-Patterns](https://codefresh.io/blog/argo-cd-anti-patterns-for-gitops/)
- [GitOps Anti-Patterns for Multi-Team Organizations](https://taraskohut.medium.com/a-modern-gitops-guide-for-multi-team-organizations-part-1-anti-patterns-d9e8f98403bc)
- [SchemaHero - GitOps for Database Schemas](https://github.com/schemahero/schemahero)
- [GitOps Drift Detection and Auto-Remediation](https://medium.com/@codingkarma/building-a-gitops-drift-detection-auto-remediation-pipeline-with-argocd-github-actions-and-f72545c63fdf)