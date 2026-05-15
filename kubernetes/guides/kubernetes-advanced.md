# Kubernetes — Référence avancée

## Workload patterns

### Init Containers

Exécutés séquentiellement AVANT le conteneur principal. Utile pour : migrations DB, téléchargement config, attente d'un service.

```yaml
initContainers:
  - name: wait-for-db
    image: busybox
    command: ['sh', '-c', 'until nc -z postgres 5432; do sleep 2; done']
  - name: flyway-migrate
    image: flyway/flyway
    args: ['migrate']
```

### Sidecar Containers (K8s 1.28+)

```yaml
initContainers:
  - name: log-shipper
    image: fluent/fluent-bit
    restartPolicy: Always  # ← sidecar natif, tourne toute la vie du pod
```

### Jobs patterns

```yaml
# Job parallèle avec completion count
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-process
spec:
  completions: 10
  parallelism: 3
  backoffLimit: 3
  activeDeadlineSeconds: 600
  template:
    spec:
      restartPolicy: Never
```

## Autoscaling

### HPA avec métriques custom

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Pods
      pods:
        metric:
          name: requests_per_second
        target:
          type: AverageValue
          averageValue: "100"
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # attendre 5min avant scale down
    scaleUp:
      stabilizationWindowSeconds: 60
```

### VPA (Vertical Pod Autoscaler)

Ajuste automatiquement les requests/limits CPU et mémoire.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: myapp-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  updatePolicy:
    updateMode: Auto  # ou Off (recommandations seulement)
```

## Sécurité avancée

### Pod Security Standards

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secure-ns
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Pod conforme au niveau restricted

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
```

### External Secrets

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: conjur
    kind: ClusterSecretStore
  target:
    name: db-secret
  data:
    - secretKey: password
      remoteRef:
        key: myapp/db/password
```

## Production hardening

### PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 2  # ou maxUnavailable: 1
  selector:
    matchLabels:
      app: myapp
```

### Topology Spread

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: myapp
```

### Priority Classes

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: critical
value: 1000000
globalDefault: false
description: "Pour les services critiques"
```

## Troubleshooting avancé

### Debug containers éphémères

```bash
# Ajouter un shell de debug à un pod en cours
kubectl debug -it myapp-pod --image=busybox --target=myapp

# Copier un pod avec debug
kubectl debug myapp-pod -it --copy-to=myapp-debug --container=myapp -- sh
```

### ResourceQuota debugging

```bash
kubectl describe resourcequota -n myns
kubectl get events -n myns --field-selector reason=FailedCreate
```

## Observabilité

### ServiceMonitor (Prometheus Operator)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
```

### Log aggregation

```yaml
# Promtail DaemonSet scrape les logs de tous les pods
# Convention : logs en JSON sur stdout
{"level":"INFO","msg":"Request processed","duration_ms":42,"path":"/api/users"}
```

## Multi-tenancy

### Isolation par namespace

```yaml
# ResourceQuota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"

# LimitRange (defaults pour les pods sans spec)
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: team-a
spec:
  limits:
    - default:
        cpu: 500m
        memory: 256Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      type: Container
```

## GitOps

### ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/org/repo.git
    path: deployments/overlays/prod
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Pitfalls K8s

### /etc/hosts est en lecture seule dans les pods

En K8s, `/etc/hosts` est monté par le kubelet et ne peut pas être modifié par le processus applicatif ou les init containers (même en root). Ce fichier est reconstitué à chaque redémarrage.

**Impact** : les tests E2E ou les scripts qui écrivent dans `/etc/hosts` pour résoudre des noms d'hôtes personnalisés échouent silencieusement.

**Solution** : utiliser le routing path-based (ingress) plutôt que les headers Host. Configurer les URLs via variables d'environnement pointant sur les ClusterIPs ou les services K8s.

```yaml
# ✗ Ne fonctionne pas en K8s (init container ne peut pas écrire /etc/hosts)
initContainers:
  - name: hosts-setup
    command: ["sh", "-c", "echo '10.0.0.1 myapp.local' >> /etc/hosts"]  # FAIL

# ✓ Utiliser des env vars avec l'URL ClusterIP
env:
  - name: APP_URL
    value: "http://myapp-service:8080/api"
```

### Quarkus — chargement de configuration supplémentaire

Quarkus JVM (distribution `/deployments/`) charge automatiquement les propriétés depuis `./config/application.properties` au démarrage (priorité haute). Monter un ConfigMap dans `/deployments/config/` permet de surcharger la configuration sans rebuilder l'image.

```yaml
# Deployment
volumeMounts:
  - name: app-config
    mountPath: /deployments/config
    readOnly: true
volumes:
  - name: app-config
    configMap:
      name: myapp-config
---
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
data:
  application.properties: |
    quarkus.datasource.jdbc.url=jdbc:postgresql://db:5432/mydb
    mp.messaging.incoming.my-channel.connector=smallrye-kafka
```
