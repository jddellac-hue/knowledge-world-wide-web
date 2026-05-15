# Cloud Foundry cf CLI — Référence expert

Source : docs.cloudfoundry.org, cli.cloudfoundry.org/en-US/v8/, v3-apidocs.cloudfoundry.org

---

## 1. cf push — Référence complète des flags

```bash
# Déploiement standard
cf push APP-NAME

# Rolling deployment (zero-downtime)
cf push APP-NAME --strategy rolling

# Canary deployment (déploie 1 instance, pause)
cf push APP-NAME --strategy canary

# Canary graduel (cf CLI v8.8.0+)
cf push APP-NAME --strategy canary --instance-steps 1,20,45,80,100

# Parallélisme rolling (par défaut 1)
cf push APP-NAME --strategy rolling --max-in-flight 5

# Push sans démarrer (staging seulement)
cf push APP-NAME --no-start

# Push sans routes (workers, tasks)
cf push APP-NAME --no-route

# Manifest spécifique
cf push -f /path/to/manifest.yml
cf push -f manifest.yml --vars-file vars-prod.yml
cf push --var host=myapp-staging

# Source
cf push APP-NAME -p /path/to/app
cf push APP-NAME -p app.jar
cf push APP-NAME -p app.zip

# Buildpack
cf push APP-NAME -b java_buildpack
cf push APP-NAME -b https://github.com/cloudfoundry/java-buildpack.git#v4.50
cf push APP-NAME -b null       # skip detection (binary deploy)

# Stack
cf push APP-NAME -s cflinuxfs4

# Ressources
cf push APP-NAME -m 512M       # mémoire
cf push APP-NAME -k 1G         # disque
cf push APP-NAME -i 3          # instances

# Docker
CF_DOCKER_PASSWORD=secret cf push APP-NAME --docker-image registry/image:tag --docker-username user

# Droplet pré-compilé (promotion cross-env)
cf push APP-NAME --droplet /path/to/droplet.tgz

# Commande de démarrage custom
cf push APP-NAME -c "bundle exec puma -p \$PORT"

# Timeout de démarrage
cf push APP-NAME --app-start-timeout 180

# Health check
cf push APP-NAME --health-check-type http

# Route aléatoire (évite collisions)
cf push APP-NAME --random-route

# Ne pas attendre le démarrage complet
cf push APP-NAME --no-wait

# Debug API
cf push APP-NAME -v
CF_TRACE=/tmp/trace.log cf push APP-NAME
```

---

## 2. Stratégies de déploiement

### Rolling deployment — comment ça marche

1. `cf push --strategy rolling` stage un nouveau droplet
2. Le `cc_deployment_updater` démarre le travail en arrière-plan
3. Démarre `max_in_flight` (défaut: 1) nouvelles instances web
4. Attend que les nouvelles instances passent les health checks
5. Supprime le même nombre d'anciennes instances
6. Répète 3-5 jusqu'à remplacement complet
7. Redémarre tous les processus non-web (workers) en bloc
8. Statut `DEPLOYED`

**Pendant le déploiement** : DEUX versions servent du trafic simultanément.

```bash
# Vérifier le statut d'un déploiement actif
cf curl "/v3/deployments?app_guids=$(cf app APP-NAME --guid)&status_values=ACTIVE"
```

### Canary deployment

```bash
# Déployer le canary (1 instance, pause)
cf push APP-NAME --strategy canary

# Valider puis continuer (devient rolling)
cf continue-deployment APP-NAME

# Annuler si le canary est mauvais
cf cancel-deployment APP-NAME
```

### Blue-Green — procédure manuelle exacte

```bash
# 1. Push Green (nouvelle version) avec route temporaire
cf push Green -f manifest-v2.yml
cf map-route Green example.com --hostname myapp-temp
# Tester via myapp-temp.example.com

# 2. Router le trafic prod vers Green
cf map-route Green example.com --hostname myapp
# Les deux versions reçoivent du trafic

# 3. Couper le trafic vers Blue
cf unmap-route Blue example.com --hostname myapp
# Tout le trafic va vers Green

# 4. Cleanup
cf unmap-route Green example.com --hostname myapp-temp
cf delete-route example.com --hostname myapp-temp -f
# Garder Blue pour rollback rapide

# ROLLBACK : re-router vers Blue
cf map-route Blue example.com --hostname myapp
cf unmap-route Green example.com --hostname myapp
```

### Annuler un déploiement en cours

```bash
cf cancel-deployment APP-NAME
```

**Attention** : annuler ne restaure PAS les changements de variables d'environnement ni les bindings de services. Uniquement le code (droplet).

---

## 3. Rollback — procédures critiques

### Rollback via revisions (méthode recommandée)

```bash
# Lister les révisions
cf revisions APP-NAME

# Détails d'une révision
cf revision APP-NAME --version 3

# Rollback (crée un nouveau déploiement rolling avec le droplet de la révision)
cf rollback APP-NAME --version 3
```

**Limites** : CAPI garde 100 révisions max, mais seulement les 5 derniers droplets. On ne peut rollback que vers un droplet encore présent.

### Rollback via droplet (manuel)

```bash
# Lister les droplets
cf droplets APP-NAME

# Option A : avec downtime
cf stop APP-NAME
cf set-droplet APP-NAME PREVIOUS-DROPLET-GUID
cf start APP-NAME

# Option B : rolling (zero downtime, via API)
APP_GUID=$(cf app APP-NAME --guid)
cf curl /v3/deployments -X POST -d "{
  \"droplet\": {\"guid\": \"PREVIOUS-DROPLET-GUID\"},
  \"strategy\": \"rolling\",
  \"relationships\": {\"app\": {\"data\": {\"guid\": \"${APP_GUID}\"}}}
}"
```

### Rollback via droplet téléchargé (cross-env)

```bash
# Sauvegarder un bon droplet
cf download-droplet APP-NAME --path /tmp/good-droplet.tgz

# Après un mauvais déploiement
cf push APP-NAME --droplet /tmp/good-droplet.tgz --strategy rolling
```

### Rollback d'un rolling deployment en cours

```bash
cf cancel-deployment APP-NAME
```

### Rollback d'un cf push standard échoué

```bash
# Si le staging a échoué → ancien droplet toujours actif
cf start APP-NAME

# Si le staging a réussi mais l'app crash
cf droplets APP-NAME
cf set-droplet APP-NAME OLD-DROPLET-GUID
cf restart APP-NAME
```

---

## 4. SSH et tunneling base de données

### Shell interactif

```bash
cf ssh APP-NAME                    # instance 0
cf ssh APP-NAME -i 2               # instance 2
cf ssh APP-NAME --process worker   # process type worker
cf ssh APP-NAME -c "ps aux"        # commande non-interactive
cf ssh APP-NAME --force-pseudo-tty # forcer le TTY (top, vim)
```

### Tunneling base de données

```bash
# 1. Récupérer les credentials
cf create-service-key MY-DB EXTERNAL-KEY
cf service-key MY-DB EXTERNAL-KEY
# Noter: hostname, port, username, password, dbname

# 2. Ouvrir le tunnel (terminal séparé)
cf ssh APP-NAME -L LOCAL_PORT:DB_HOSTNAME:DB_PORT -N
```

**MySQL :**
```bash
cf ssh myapp -L 63306:mysql-host.service.internal:3306 -N &
mysql -u user -h 127.0.0.1 -p -D mydb -P 63306
```

**PostgreSQL :**
```bash
cf ssh myapp -L 65432:postgres-host.service.internal:5432 -N &
psql "host=127.0.0.1 port=65432 dbname=mydb user=pguser password=pgpass"
```

**Oracle :**
```bash
cf ssh myapp -L 61521:oracle-host.service.internal:1521 -N &
sqlplus user/password@//127.0.0.1:61521/SERVICE_NAME
```

**Redis :**
```bash
cf ssh myapp -L 63790:redis-host.service.internal:6379 -N &
redis-cli -h 127.0.0.1 -p 63790 -a password
```

**RabbitMQ Management :**
```bash
cf ssh myapp -L 65672:rabbitmq-host.service.internal:15672 -N &
# Ouvrir http://127.0.0.1:65672 dans le navigateur
```

---

## 5. Tasks (jobs ponctuels)

```bash
# Task avec commande custom
cf run-task APP-NAME --command "rake db:migrate" --name db-migration

# Task avec ressources custom
cf run-task APP-NAME --command "python batch.py" --name batch -m 2G -k 4G

# Lister les tasks
cf tasks APP-NAME

# Annuler une task
cf terminate-task APP-NAME TASK-ID
```

Le conteneur est détruit après exécution. Les logs vont dans le firehose.

---

## 6. restart vs restage — quand utiliser quoi

| Changement | restart | restage |
|------------|---------|---------|
| Variable d'env applicative | OUI | non |
| Variable utilisée par le buildpack | non | OUI |
| Bind/unbind service | OUI | non |
| Changement de buildpack | non | OUI |
| Changement de stack | non | OUI |
| Besoin d'un nouveau droplet | non | OUI |

```bash
cf restart APP-NAME                  # réutilise le droplet existant
cf restage APP-NAME                  # recompile le droplet
cf restart-app-instance APP-NAME 0   # restart une seule instance
```

---

## 7. Opérations réseau avancées

### Container-to-container networking

```bash
cf add-network-policy frontend backend --protocol tcp --port 8080
cf add-network-policy frontend backend -s other-space -o other-org --protocol tcp --port 8080-8090
cf network-policies
cf remove-network-policy frontend backend --protocol tcp --port 8080
```

### Isolation segments

```bash
cf create-isolation-segment my-segment
cf enable-org-isolation my-org my-segment
cf set-org-default-isolation-segment my-org my-segment
cf set-space-isolation-segment my-space my-segment
cf isolation-segments
```

### Application Security Groups (ASG)

```bash
cf create-security-group my-asg rules.json
cf bind-running-security-group my-asg
cf bind-security-group my-asg my-org --space my-space
cf security-groups
```

---

## 8. Gestion des permissions

```bash
# Rôles org
cf set-org-role USERNAME MY-ORG OrgManager
cf set-org-role USERNAME MY-ORG BillingManager
cf set-org-role USERNAME MY-ORG OrgAuditor

# Rôles space
cf set-space-role USERNAME MY-ORG MY-SPACE SpaceManager
cf set-space-role USERNAME MY-ORG MY-SPACE SpaceDeveloper
cf set-space-role USERNAME MY-ORG MY-SPACE SpaceAuditor
cf set-space-role USERNAME MY-ORG MY-SPACE SpaceSupporter

# Lister
cf org-users MY-ORG
cf space-users MY-ORG MY-SPACE
```

---

## 9. cf curl — accès API brut

```bash
# Apps
cf curl /v3/apps
cf curl /v3/apps/$(cf app APP-NAME --guid)
cf curl /v3/apps/$(cf app APP-NAME --guid)/processes
cf curl /v3/apps/$(cf app APP-NAME --guid)/env

# Déploiements
cf curl /v3/deployments?app_guids=$(cf app APP-NAME --guid)

# Rollback via API
cf curl /v3/deployments -X POST -d '{
  "revision": {"guid": "REVISION-GUID"},
  "relationships": {"app": {"data": {"guid": "APP-GUID"}}}
}'

# Révisions
cf curl /v3/apps/$(cf app APP-NAME --guid)/revisions
cf curl /v3/apps/$(cf app APP-NAME --guid)/revisions/deployed

# Token OAuth pour curl externe
TOKEN=$(cf oauth-token)
curl -H "Authorization: $TOKEN" "https://api.cf.example.com/v3/apps"
```

---

## 10. Troubleshooting

### Workflow de diagnostic

```bash
cf app APP-NAME                    # état, instances, mémoire
cf events APP-NAME                 # événements (crash, restart, deploy)
cf logs APP-NAME --recent          # logs récents
cf logs APP-NAME                   # logs temps réel
cf env APP-NAME                    # variables d'environnement
cf ssh APP-NAME                    # shell dans le conteneur
```

### Crash loop

```bash
# Vérifier le code de sortie dans les events
cf events APP-NAME
# 137 = OOM (mémoire insuffisante)
# 255 = erreur générique
# 1   = erreur applicative

# Vérifier la mémoire
cf app APP-NAME
cf scale APP-NAME -m 1G

# Vérifier que l'app écoute sur $PORT
cf ssh APP-NAME -c "echo \$PORT"

# Vérifier le health check
cf get-health-check APP-NAME
cf set-health-check APP-NAME process   # pour les non-web
```

### Staging failures

```bash
cf logs APP-NAME --recent | grep STG
cf buildpacks                      # buildpacks disponibles
cf push APP-NAME -b java_buildpack # forcer un buildpack
export CF_STAGING_TIMEOUT=30       # timeout en minutes
```

---

## 11. Manifest.yml avancé

### Multi-process

```yaml
applications:
- name: my-app
  processes:
    - type: web
      command: java -jar app.jar
      instances: 3
      memory: 1G
      health-check-type: http
      health-check-http-endpoint: /actuator/health
      readiness-health-check-type: http
      readiness-health-check-http-endpoint: /actuator/health/readiness
      timeout: 120
    - type: worker
      command: java -cp app.jar com.example.Worker
      instances: 2
      memory: 512M
      health-check-type: process
      no-route: true
```

### Sidecars

```yaml
applications:
- name: my-app
  sidecars:
    - name: log-forwarder
      process_types: ['web', 'worker']
      command: ./log-forwarder
      memory: 128M
```

### Variables

```yaml
applications:
- name: myapp
  instances: ((instances))
  memory: ((memory))
  routes:
    - route: ((host)).example.com
```

```bash
cf push --vars-file vars-prod.yml
cf push --var host=myapp-staging
```

### Docker

```yaml
applications:
- name: my-docker-app
  docker:
    image: registry/team/app:v2.1.0
    username: deploy-bot
```

```bash
CF_DOCKER_PASSWORD=secret cf push -f manifest.yml
```

### YAML anchors (DRY)

```yaml
defaults: &defaults
  buildpacks: [java_buildpack]
  memory: 1G
  health-check-type: http
  health-check-http-endpoint: /health

applications:
- name: api
  <<: *defaults
  instances: 4
- name: admin
  <<: *defaults
  instances: 2
  memory: 512M    # override
```

---

## 12. Feature flags

```bash
cf feature-flags
cf enable-feature-flag diego_docker     # push Docker images
cf enable-feature-flag diego_cnb        # Cloud Native Buildpacks
cf enable-feature-flag service_instance_sharing
cf disable-feature-flag user_org_creation
```

---

## 13. Plugins utiles

```bash
cf add-plugin-repo CF-Community https://plugins.cloudfoundry.org

# Tunnel DB en une commande
cf install-plugin cf-service-connect -r CF-Community
cf connect-to-service APP-NAME MY-DB

# Top interactif
cf install-plugin top -r CF-Community
cf top

# Multi-targets
cf install-plugin targets -r CF-Community
cf save-target prod
cf set-target prod
```

---

## 14. Commandes d'urgence

```bash
# ROLLBACK IMMÉDIAT
cf rollback APP-NAME --version LAST-GOOD

# ANNULER DÉPLOIEMENT EN COURS
cf cancel-deployment APP-NAME

# STOP D'URGENCE
cf stop APP-NAME

# DIAGNOSTIC COMPLET
cf app APP-NAME && cf events APP-NAME && cf logs APP-NAME --recent

# GUID POUR API
cf app APP-NAME --guid

# FORCE RESTAGE
cf restage APP-NAME

# OPTION NUCLÉAIRE
cf delete APP-NAME -f -r && cf push APP-NAME -f manifest.yml
```
