---
name: tanzu
description: VMware Tanzu Platform (Cloud Foundry) -- architecture BOSH/Diego/Gorouter/UAA/Loggregator, Elastic Application Runtime, Tanzu Operations Manager, cf CLI, buildpacks, manifest.yml, service brokers, CredHub, isolation segments, ASG, Healthwatch, Metric Store, Scheduler, Spring Cloud Gateway, Dynatrace integration, App Metrics. Utiliser cette skill pour tout sujet lie a Tanzu, TAS, Cloud Foundry, BOSH, Diego, EAR, Ops Manager, cf push.
---

# VMware Tanzu Platform -- Guide complet

```mermaid
%%{init: {"theme": "base", "themeVariables": {
  "primaryColor": "#2C3E50", "primaryTextColor": "#FFFFFF",
  "cScale0": "#9B59B6", "cScale1": "#27AE60", "cScale2": "#E67E22",
  "cScale3": "#2980B9", "cScale4": "#E74C3C", "cScale5": "#1ABC9C"
}}}%%
mindmap
  root((🌿 Tanzu))
    📖 Core
      CF architecture
      Gorouter et routing
      Buildpacks et Diego
    📚 Guides
      cf-cli-expert.md
```
| Fichier | Description |
|---------|-------------|
| [README.md](README.md) | Point d'entrée Tanzu |
| [guides/cf-cli-expert.md](guides/cf-cli-expert.md) | CF CLI expert |

## 1. Vue d'ensemble et historique

### Lignee du produit

```
Pivotal Cloud Foundry (PCF)
  -> VMware Tanzu Application Service (TAS) for VMs
    -> Tanzu Platform for Cloud Foundry (TPCF)
      -> Elastic Application Runtime (EAR) [depuis v10.3]
```

**Tanzu Platform** est la distribution commerciale VMware/Broadcom de Cloud Foundry.
Deux runtimes coexistent :

| Runtime | Cible | Orchestrateur |
|---------|-------|---------------|
| **Elastic Application Runtime (EAR)** | Apps Cloud Foundry (cf push) | Diego + BOSH |
| **Tanzu Platform for Kubernetes** | Apps Cloud-Native (K8s) | Kubernetes |

### Versionnement actuel

| Produit | Version LTS | Version courante |
|---------|-------------|------------------|
| Tanzu Operations Manager | 3.0.x+LTS-T | 3.2.x |
| Elastic Application Runtime (Linux) | 6.0.x+LTS-T | 10.3.x |
| Elastic Application Runtime (anciennement TPCF) | 10.0.x | 10.3.x |
| Foundation Core | 3.0.32+LTS-T | 3.1.6 |

**LTS** : les versions +LTS-T recoivent des patches de securite pendant 2+ ans. Le suffixe `+LTS-T` apparait dans les noms de fichier.

---

## 2. Architecture de la plateforme

### 2.1 Vue macro

```mermaid
flowchart TD
    classDef proc fill:#D1ECF1,stroke:#0C5460,color:#0C5460
    classDef ok   fill:#D4EDDA,stroke:#155724,color:#155724
    classDef key  fill:#CCE5FF,stroke:#004085,color:#004085
    classDef warn fill:#FFF3CD,stroke:#856404,color:#333

    LB["Load Balancer"]:::key
    GR["Gorouter<br/>HTTP L7 routing"]:::proc
    CC["Cloud Controller<br/>(API)"]:::proc
    DC["Diego Cells<br/>(containers)"]:::ok
    UAA["UAA<br/>Auth / SSO"]:::proc
    GD["Garden<br/>container runtime"]:::ok

    LB --> GR --> CC & DC
    CC --> UAA
    DC --> GD
```

### 2.2 Types de VMs

| Categorie | Role | Exemples |
|-----------|------|----------|
| **Component VMs** | Infrastructure plateforme | Cloud Controller, Diego Brain, Gorouter, UAA, NATS, Doppler |
| **Host VMs (Diego Cells)** | Hebergent les applications | Diego Cell (Linux), Diego Cell (Windows) |
| **Service VMs** | Services manages | MySQL, RabbitMQ, Valkey, Redis |
| **BOSH Director** | Orchestre tout | VM unique qui gere toutes les autres |

---

## 3. BOSH -- Orchestrateur d'infrastructure

### Qu'est-ce que BOSH ?

BOSH est un outil de release engineering qui provisionne des VMs et du logiciel sur votre IaaS. Il cree, deploie, met a jour et ressuscite des VMs a partir de releases signees.

### Concepts fondamentaux

| Concept | Definition |
|---------|-----------|
| **Director** | VM centrale qui orchestre les deployments. Un Director peut gerer des milliers de VMs. |
| **Stemcell** | Image OS versionnee minimale (Ubuntu Jammy 22.04). Contient : skeleton OS + BOSH Agent + config securisee. |
| **Release** | Repertoire contenant le source code, scripts de demarrage, artefacts binaires et manifest BOSH pour deployer un service. |
| **Deployment** | Ensemble de VMs instanciees a partir d'un manifest, d'une release et d'un stemcell. |
| **Manifest** | Fichier YAML decrivant la topologie souhaitee (VMs, jobs, proprietes, reseaux). |
| **Errand** | Tache ponctuelle executee sur une VM BOSH (ex : smoke tests, migration DB). |
| **CPI** | Cloud Provider Interface -- adaptateur IaaS (vSphere, AWS, GCP, Azure, OpenStack). |

### Stemcells

```
Stemcell = OS minimal (Ubuntu Jammy 22.04 LTS)
         + BOSH Agent
         + Config securisee par defaut

Lifecycle :
  1. BOSH Director telecharge le stemcell
  2. CPI cree une VM a partir du stemcell sur l'IaaS
  3. BOSH Agent sur la VM contacte le Director
  4. Director installe les jobs (packages + configs)
```

**Versions courantes** :

| Stemcell | OS | Statut |
|----------|----|--------|
| Jammy 1.x | Ubuntu 22.04 LTS | **Actif** (recommande) |
| Bionic 1.x | Ubuntu 18.04 | **Fin de support** -- migrer vers Jammy |

**Stacks (pour les apps)** :

| Stack | OS | Statut |
|-------|----|--------|
| `cflinuxfs4` | Ubuntu Jammy 22.04 | **Actif** |
| `cflinuxfs3` | Ubuntu Bionic 18.04 | **Fin de support** |

### BOSH DNS

Le Director depose un serveur BOSH DNS sur chaque VM deployee, permettant :
- Decouverte de services entre VMs par nom DNS
- Load-balancing cote client (selection aleatoire d'une VM saine)

### Commandes BOSH essentielles

```bash
# Cibler un Director
bosh alias-env my-env -e 192.168.1.25 --ca-cert /path/to/ca.pem
bosh -e my-env login

# Deployer / mettre a jour
bosh -e my-env -d my-deployment deploy manifest.yml
bosh -e my-env -d my-deployment deploy manifest.yml -o ops-file.yml -v key=value

# Gestion des VMs
bosh -e my-env -d my-deployment vms                    # lister les VMs
bosh -e my-env -d my-deployment instances --ps         # instances + processus
bosh -e my-env -d my-deployment ssh diego-cell/0       # SSH dans une VM
bosh -e my-env -d my-deployment ssh redis/0 "ls -la"   # commande distante
bosh -e my-env -d my-deployment recreate diego-cell/0  # recreer une VM
bosh -e my-env -d my-deployment restart router/0       # redemarrer un job

# Logs
bosh -e my-env -d my-deployment logs diego-cell/0      # telecharge /var/vcap/sys/log
bosh -e my-env -d my-deployment logs --follow router/0 # streaming en temps reel

# Stemcells
bosh -e my-env upload-stemcell bosh-stemcell-1.234-vsphere-esxi-ubuntu-jammy-go_agent.tgz
bosh -e my-env stemcells                               # lister les stemcells

# Errands
bosh -e my-env -d cf run-errand smoke-tests
bosh -e my-env -d cf run-errand push-apps-manager

# Health
bosh -e my-env -d my-deployment cloud-check            # detecter et reparer les problemes
bosh -e my-env tasks --recent=20                       # taches recentes du Director
```

### Variables et CredHub

BOSH utilise CredHub comme config server. Toute variable `((variable-name))` dans un manifest est resolue depuis CredHub au moment du deploy.

```yaml
# Exemple dans un manifest BOSH
instance_groups:
- name: mysql
  properties:
    admin_password: ((mysql_admin_password))  # Resolve depuis CredHub
```

Namespacing automatique : `/bosh-director/deployment-name/variable-name`

---

## 4. Diego -- Orchestration de conteneurs

### Architecture Diego

```
                    +------------------+
                    |  Cloud Controller|
                    |     (API)        |
                    +--------+---------+
                             |
                    +--------v---------+
                    |    CC-Bridge     |  (stager, nsync, TPS)
                    +--------+---------+
                             |
                    +--------v---------+
                    |       BBS        |  (Bulletin Board System)
                    |   (diego-api VM) |  -- stocke l'etat du cluster
                    +--------+---------+
                             |
              +--------------+--------------+
              |                             |
     +--------v---------+         +--------v---------+
     |   Auctioneer     |         |     Locket       |
     | (scheduler VM)   |         | (locks distribues)|
     +--------+---------+         +------------------+
              |
     +--------v---------+
     |   Rep (Cell)     |  -- 1 par Diego Cell
     |   + Garden       |  -- runtime conteneur
     |   + Route-Emitter|  -- annonce les routes
     |   + Loggr Agent  |  -- forwarde logs/metriques
     +------------------+
```

### Composants en detail

| Composant | VM | Role |
|-----------|------|------|
| **BBS** | diego-api | Maintient l'etat du cluster (DesiredLRP vs ActualLRP). API RPC. Stocke dans MySQL. |
| **Auctioneer** | scheduler | Distribue le travail aux Cells par encheres (auction). Contacte les Reps via SSL/TLS. |
| **Locket** | diego-api | Service de locks distribues et presence des composants. |
| **Rep** | diego-cell | Represente une Cell. Gere le cycle de vie des conteneurs, rapporte au BBS. |
| **Garden** | diego-cell | Runtime conteneur (cree/detruit les conteneurs, telecharge les droplets). |
| **Route-Emitter** | diego-cell | Surveille les LRPs et emet les enregistrements de routes vers NATS/Gorouter. |
| **CC-Bridge** | api | Traduit les requetes Cloud Controller en objets Diego (stager, nsync, TPS). |
| **SSH-Proxy** | scheduler | Relaye les connexions SSH vers les instances d'apps. |

### Tasks vs Long-Running Processes (LRP)

| Type | Description | Exemple |
|------|------------|---------|
| **Task** | Operation ponctuelle, execute une fois | Staging d'une app, migration DB |
| **LRP** | Processus continu, Diego maintient le nombre d'instances desire | Instance d'application en cours d'execution |

Le BBS synchronise `DesiredLRP` (ce que Cloud Controller demande) et `ActualLRP` (ce qui tourne reellement). Si un ecart est detecte, il lance de nouvelles encheres ou envoie des ordres d'arret.

### Cycle de vie d'un `cf push`

```
1. cf CLI envoie les bits au Cloud Controller
2. Cloud Controller cree un droplet via CC-Bridge
3. CC-Bridge envoie une Task "stage" au BBS
4. BBS contacte l'Auctioneer
5. Auctioneer lance une enchere -- les Reps proposent leurs ressources
6. Le Rep gagnant cree un conteneur Garden, telecharge le buildpack
7. Le buildpack compile l'app, produit un droplet
8. Cloud Controller demande N instances (DesiredLRP) au BBS
9. L'Auctioneer distribue les LRPs aux Cells disponibles
10. Les Reps creent les conteneurs Garden avec le droplet
11. Route-Emitter annonce les routes via NATS au Gorouter
12. L'app est accessible via le Gorouter
```

### Algorithme d'encheres (Auction)

L'Auctioneer distribue les taches en evaluant les ressources disponibles (memoire, disque, CPU) sur chaque Cell. Les Reps repondent avec leur capacite. L'Auctioneer selectionne la Cell optimale en fonction de la charge et de la repartition.

**Maximum recommande** : 250 Diego Cells par deploiement Cloud Foundry.

---

## 5. Gorouter -- Routage HTTP

### Fonctionnement

```mermaid
flowchart LR
    classDef proc fill:#D1ECF1,stroke:#0C5460,color:#0C5460
    classDef ok   fill:#D4EDDA,stroke:#155724,color:#155724
    classDef key  fill:#CCE5FF,stroke:#004085,color:#004085

    CL["Client"]:::key
    LB["Load Balancer"]:::proc
    GR["Gorouter<br/>HTTP L7"]:::proc
    CT["Conteneur<br/>(Diego Cell)"]:::ok

    CL --> LB --> GR --> CT
```

Le Gorouter est le routeur HTTP L7 qui dirige le trafic entrant vers les bonnes instances d'application.

### Enregistrement des routes

1. Route-Emitter sur chaque Diego Cell envoie des messages periodiques via NATS
2. Chaque message contient : app instance IP + port + identifiant unique
3. Le Gorouter maintient une table de routage en memoire
4. Si aucune mise a jour recue dans le TTL, la route est purgee

### Load Balancing

| Algorithme | Comportement |
|-----------|-------------|
| **Round Robin** (defaut) | Requetes distribuees une par une entre les instances |
| **Least Connection** | Requete envoyee a l'instance avec le moins de connexions ouvertes |

Option `locally-optimistic` : privilegie les instances dans la meme AZ que le Gorouter.

### Sticky Sessions

Quand une app retourne un cookie de session, le routeur genere un `VCAP_ID` unique par instance. Le client doit renvoyer les deux cookies pour maintenir la session. Si l'instance tombe, le Gorouter redirige vers une autre instance saine.

### WebSocket

Le Gorouter supporte le handshake d'upgrade WebSocket et maintient la connexion bi-directionnelle longue duree.

### TLS et securite

- **Backend TLS** : Gorouter valide l'identite des instances via TLS avec les sidecars Envoy
- **mTLS** : support de l'authentification mutuelle
- **Headers** :
  - `X-Forwarded-Proto` : schema (HTTP/HTTPS)
  - `X-Forwarded-For` : IP client
  - `X-Forwarded-Client-Cert` : metadonnees certificat client
  - `X-B3-TraceId` / `X-B3-SpanId` : tracage Zipkin
  - `X-Cf-App-Instance` : routage vers une instance specifique
- **Limite headers** : 1 MB

### Route Services

Les Route Services interceptent les requetes avant qu'elles n'atteignent l'app :

```
Client -> Gorouter -> Route Service -> Gorouter -> App
```

Headers specifiques ajoutes par le Gorouter :
- `X-CF-Forwarded-Url` : URL originale demandee
- `X-CF-Proxy-Signature` : signature de validation
- `X-CF-Proxy-Metadata` : metadonnees

### Gestion des connexions

- **Keep-Alive** : jusqu'a 100 connexions idle par backend
- **Retry transparent** : si echec TCP, instance marquee ineligible 30s, retry vers une autre (max 3)
- **Timeout backend** : 15 minutes si TCP ok mais pas de reponse
- **Erreur 502** : retourne si echec de connexion sans retry possible

---

## 6. Cloud Controller -- API de la plateforme

### Role

Le Cloud Controller (CC) est le point d'entree API de la plateforme. Il gere le cycle de vie des applications, les orgs, spaces, services, et les roles utilisateur.

### API V3

```
Endpoint de base : https://api.system.example.com/v3/

Ressources principales :
  /v3/organizations
  /v3/spaces
  /v3/apps
  /v3/packages
  /v3/droplets
  /v3/deployments
  /v3/service_instances
  /v3/service_bindings
  /v3/routes
  /v3/domains
  /v3/buildpacks
```

### Modele Org/Space/App

```
Foundation (1 deploiement Cloud Foundry)
  +-- Org (compte de developpement)
  |     +-- Space (environnement)
  |     |     +-- App 1
  |     |     +-- App 2
  |     |     +-- Service Instance (MySQL, Redis...)
  |     |     +-- Route
  |     +-- Space staging
  |     +-- Space production
  +-- Org equipe-b
        +-- Space dev
        +-- Space prod
```

### Roles et permissions

#### Roles Organisation

| Role | Permissions |
|------|-----------|
| **Admin** | Actions operationnelles sur toutes les orgs/spaces (scope `cloud_controller.admin`) |
| **Admin Read-Only** | Lecture seule sur toutes les ressources (scope `cloud_controller.admin_read_only`) |
| **Global Auditor** | Lecture seule sauf secrets (variables env) |
| **Org Manager** | Administre l'org, cree des spaces, gere les quotas et roles |
| **Org Auditor** | Lecture seule sur les infos utilisateurs et quotas |
| **Org Billing Manager** | Gere la facturation |
| **Org User** | Voit la liste des utilisateurs de l'org |

#### Roles Space

| Role | Permissions |
|------|-----------|
| **Space Manager** | Gere le space, invite des utilisateurs |
| **Space Developer** | **Role principal dev** : push apps, bind services, gere les routes |
| **Space Auditor** | Lecture seule du space |
| **Space Supporter** | Debug et troubleshoot (API V3 uniquement) |

### Cloud Controller Blobstore

Stocke les packages (code source uploade), les droplets (resultat du staging), les buildpacks, et le resource cache.

**Puma** (depuis TPCF 10.2) : le serveur web du Cloud Controller est passe a Puma, permettant l'utilisation de plusieurs coeurs CPU pour le scaling vertical.

---

## 7. UAA -- Authentification et autorisation

### Vue d'ensemble

UAA (User Account and Authentication) est un serveur d'identite OAuth2 multi-tenant. C'est le systeme central d'authentification de Cloud Foundry.

### Protocoles supportes

| Protocole | Usage |
|-----------|-------|
| **OAuth 2.0** | Emission de tokens pour les apps clients |
| **OpenID Connect 1.0** | Federation avec des IDPs externes, SSO |
| **SAML 2.0** | Federation avec des IDPs SAML (UAA agit comme SP) |
| **LDAP** | Authentification directe contre un annuaire |
| **SCIM 1.0** | Gestion des utilisateurs et groupes |

### Architecture

```
                    +--------+
                    | Client |  (cf CLI, Apps Manager, app custom)
                    +---+----+
                        |
                   +----v----+
                   |   UAA   |  (OAuth2 Authorization Server)
                   +----+----+
                        |
           +------------+-------------+
           |            |             |
      +----v---+  +----v----+  +----v----+
      | LDAP   |  | SAML    |  | Internal|
      | Server |  | IdP     |  | Users   |
      +--------+  +---------+  +---------+
```

### Instances UAA

Cloud Foundry maintient deux instances UAA separees :
1. **UAA du BOSH Director** : bootstrap du Director
2. **UAA du deployment CF** : authentification des utilisateurs et apps

**Important** : se connecter a un runtime ne connecte pas automatiquement aux autres.

### Scopes principaux

| Scope | Acces |
|-------|-------|
| `cloud_controller.read` | Lecture des ressources CC |
| `cloud_controller.write` | Creation/modification des ressources CC |
| `cloud_controller.admin` | Admin complet |
| `uaa.admin` | Admin UAA |
| `scim.read` / `scim.write` | Gestion des utilisateurs |
| `openid` | Profil utilisateur OpenID Connect |

### Configuration SAML

```
Metadata endpoint : https://login.system.example.com/saml/metadata

Configuration :
1. Enregistrer l'UAA comme SP dans votre IdP SAML
2. Configurer l'IdP dans UAA (metadata URL ou XML)
3. Le nameID SAML est matche a user.username dans UAA
```

### Configuration LDAP

Integration simple ne necessitant que la configuration cote UAA :
- URL du serveur LDAP
- Base DN de recherche
- Filtre de recherche utilisateur
- Le username est derive de l'input utilisateur

### Commandes UAAC

```bash
# Se connecter a l'UAA
uaac target https://uaa.system.example.com
uaac token client get admin -s <admin-client-secret>

# Lister les clients
uaac clients

# Creer un utilisateur
uaac user add jean.dupont --emails jean.dupont@example.com --password <pwd>

# Attribuer un role
uaac member add cloud_controller.admin jean.dupont
```

---

## 8. Loggregator -- Agregation de logs et metriques

### Architecture

```
Apps / Composants
      |
      v
+------------------+     +------------------+
| Forwarder Agent  | --> | Loggregator Agent| --> Doppler
| (chaque VM)      |     | (chaque VM)      |     |
+------------------+     +------------------+     |
                                                   v
                          +-------------------------------------------+
                          |                  Doppler                  |
                          | (buffer temporaire, replique par consumer)|
                          +----+------------------+------------------+
                               |                  |                  |
                          +----v----+    +--------v--------+  +-----v------+
                          | Traffic |    | Reverse Log     |  | Syslog     |
                          |Controller|   | Proxy (RLP)     |  | Agent      |
                          |(V1 WS)  |    | (V2 gRPC)       |  | (RFC 5424) |
                          +---------+    +--------+--------+  +-----+------+
                                                  |                  |
                                         +--------v--------+  +-----v------+
                                         |   Log Cache     |  | Syslog     |
                                         | (stockage court |  | Drain      |
                                         |  terme, PromQL) |  | (externe)  |
                                         +-----------------+  +------------+
```

### Composants

| Composant | Role |
|-----------|------|
| **Forwarder Agent** | Collecte logs et metriques depuis les apps et composants locaux |
| **Prom Scraper** | Aggrege les metriques via endpoints Prometheus exposition |
| **Loggregator Agent** | Distribue les donnees a un pool de 5 Dopplers (aleatoire) |
| **Doppler** | Bufferise les logs/metriques, les forward aux consumers |
| **Traffic Controller** | V1 Firehose (WebSocket). Deconnecte les consumers lents. |
| **Reverse Log Proxy (RLP)** | V2 Firehose (gRPC). V2 Envelopes. Drop les enveloppes si le consumer est trop lent. |
| **RLP Gateway** | Acces HTTP au V2 Firehose (JSON-encoded V2 Envelopes) |
| **Syslog Agent** | Logs au format RFC 5424 vers des destinations aggregees ou par-app |
| **Log Cache** | Stockage court terme, accessible via API et cf CLI plugin |
| **System Metrics Agent** | Metriques au niveau VM (CPU, memoire, disque) |

### Firehose

Le Firehose est le flux agrege de TOUS les logs d'applications et metriques de composants de la plateforme.

- **V1 Firehose** : via Traffic Controller, WebSocket
- **V2 Firehose** : via RLP, gRPC (recommande)

### Nozzles

Les Nozzles sont des consumers connectes au Firehose pour router les metriques vers des systemes externes (Datadog, Splunk, Dynatrace, etc.).

### Commandes de log

```bash
# Streaming en temps reel
cf logs my-app

# Logs recents (buffer)
cf logs my-app --recent

# Log Cache (via plugin)
cf install-plugin -r CF-Community "log-cache"
cf tail my-app
cf query 'cpu{source_id="APP-GUID"}'
```

---

## 9. Experience developpeur

### 9.1 cf CLI -- Commandes essentielles

```bash
# ---- Authentification ----
cf login -a https://api.system.example.com -o my-org -s my-space
cf login -a https://api.system.example.com --sso  # SSO via navigateur
cf target -o my-org -s my-space

# ---- Deploiement ----
cf push my-app                           # deploie depuis le repertoire courant
cf push my-app -f manifest-prod.yml      # avec un manifest specifique
cf push my-app -p target/app.jar         # chemin vers l'artefact
cf push my-app --strategy rolling        # deploiement rolling (zero-downtime)
cf push my-app --strategy canary         # deploiement canary
cf push my-app --strategy canary --instance-steps 5,10,20  # canary graduel

# ---- Scaling ----
cf scale my-app -i 5                     # 5 instances (horizontal)
cf scale my-app -m 1G                    # 1 GB memoire (vertical)
cf scale my-app -k 2G                    # 2 GB disque

# ---- Monitoring ----
cf logs my-app                           # streaming temps reel
cf logs my-app --recent                  # buffer recent
cf events my-app                         # evenements (crashes, restages)
cf app my-app                            # etat detaille

# ---- SSH ----
cf ssh my-app                            # SSH interactif (instance 0)
cf ssh my-app -i 2                       # instance specifique
cf ssh my-app -c "cat /app/config.yml"   # commande distante

# ---- Services ----
cf marketplace                           # lister les services disponibles
cf marketplace -e mysql                  # details d'un service
cf create-service p-mysql db-small my-db # creer une instance
cf bind-service my-app my-db             # binder a l'app
cf unbind-service my-app my-db           # debinder
cf delete-service my-db                  # supprimer l'instance
cf service my-db                         # statut de l'instance

# ---- Routes ----
cf routes                                # lister les routes
cf map-route my-app example.com --hostname api  # ajouter une route
cf unmap-route my-app example.com --hostname api  # retirer une route
cf create-route my-space example.com --hostname new-api  # creer sans mapper

# ---- Variables d'environnement ----
cf set-env my-app SPRING_PROFILES_ACTIVE prod
cf env my-app                            # voir toutes les vars (VCAP_SERVICES, etc.)
cf restage my-app                        # necessaire apres changement de buildpack/env

# ---- Gestion d'app ----
cf restart my-app                        # restart (pas de re-staging)
cf restage my-app                        # restage (re-execute le buildpack)
cf stop my-app
cf start my-app
cf delete my-app -r                      # supprime l'app et ses routes
```

### 9.2 Manifest.yml

```yaml
---
applications:
- name: my-api
  memory: 1G
  disk_quota: 512M
  instances: 3
  path: target/my-api.jar
  buildpacks:
    - java_buildpack_offline
  stack: cflinuxfs4
  timeout: 180
  health-check-type: http
  health-check-http-endpoint: /actuator/health

  env:
    SPRING_PROFILES_ACTIVE: cloud
    JBP_CONFIG_OPEN_JDK_JRE: '{ jre: { version: 17.+ } }'
    JAVA_OPTS: "-XX:MaxMetaspaceSize=256m"

  routes:
    - route: my-api.apps.example.com
    - route: my-api-internal.apps.internal

  services:
    - my-database
    - my-rabbitmq
    - my-config-server

  processes:
    - type: web
      instances: 3
      memory: 1G
    - type: worker
      instances: 1
      memory: 512M
      command: java -jar target/worker.jar
      health-check-type: process
      no-route: true

  sidecars:
    - name: log-forwarder
      process_types: ['web']
      command: ./log-forwarder
      memory: 128M
```

#### Attributs cles

| Attribut | Description | Defaut |
|----------|-----------|--------|
| `name` | Nom de l'application | - |
| `memory` | Limite memoire (M, G) | 1G |
| `disk_quota` | Espace disque (M, G) | 1G |
| `instances` | Nombre d'instances | 1 |
| `buildpacks` | Liste de buildpacks | Auto-detect |
| `stack` | Stack OS (`cflinuxfs4`) | cflinuxfs4 |
| `path` | Chemin vers les bits de l'app | `.` |
| `command` | Commande de demarrage custom | - |
| `health-check-type` | `port`, `http`, `process` | port |
| `health-check-http-endpoint` | Endpoint pour health check HTTP | `/` |
| `timeout` | Secondes allouees au demarrage | 60 |
| `no-route` | Pas de route (worker, task) | false |
| `random-route` | Route aleatoire unique | false |
| `routes` | Routes HTTP/TCP | auto |
| `services` | Instances de service a binder | - |
| `env` | Variables d'environnement | - |
| `docker.image` | Image Docker | - |
| `processes` | Processus multiples (web, worker) | - |
| `sidecars` | Processus additionnels dans le meme conteneur | - |

#### Variables dans les manifests

```yaml
# manifest.yml
applications:
- name: my-app
  instances: ((instances))
  memory: ((memory))
  routes:
    - route: ((hostname)).((domain))

# vars-prod.yml
instances: 5
memory: 2G
hostname: my-api
domain: prod.example.com
```

```bash
cf push -f manifest.yml --vars-file vars-prod.yml
```

### 9.3 Buildpacks

| Buildpack | Detection | Langage/Runtime |
|-----------|----------|-----------------|
| **java_buildpack** | `*.jar`, `*.war`, `pom.xml` | Java (OpenJDK), Spring Boot, Tomcat |
| **nodejs_buildpack** | `package.json` | Node.js, npm/yarn |
| **go_buildpack** | `go.mod`, `*.go` | Go |
| **python_buildpack** | `requirements.txt`, `setup.py`, `Pipfile` | Python, pip/pipenv |
| **ruby_buildpack** | `Gemfile` | Ruby, Bundler |
| **dotnet_core_buildpack** | `*.csproj`, `*.fsproj` | .NET Core/6+ |
| **binary_buildpack** | Declare explicitement | Binaire pre-compile |
| **staticfile_buildpack** | Fichier `Staticfile` a la racine | HTML/CSS/JS statique (nginx) |
| **nginx_buildpack** | `nginx.conf` | Nginx custom |
| **php_buildpack** | `composer.json`, `index.php` | PHP |

**Buildpack custom** :
```bash
cf push my-app -b https://github.com/cloudfoundry/java-buildpack.git#v4.50
```

**Multi-buildpack** :
```yaml
buildpacks:
  - dynatrace_buildpack
  - java_buildpack_offline
```

### 9.4 Service Brokers

#### Open Service Broker API (OSB API)

Standard ouvert decrivant comment une plateforme interagit avec des service brokers via HTTP REST.

```
Marketplace (cf marketplace)
  |
  v
Service Broker (implementation OSB API)
  |-- catalog      : GET /v2/catalog
  |-- provision    : PUT /v2/service_instances/:id
  |-- bind         : PUT /v2/service_instances/:id/service_bindings/:bid
  |-- unbind       : DELETE /v2/service_instances/:id/service_bindings/:bid
  |-- deprovision  : DELETE /v2/service_instances/:id
  |-- last_operation : GET /v2/service_instances/:id/last_operation
```

#### Binding et VCAP_SERVICES

Quand une app est bindee a un service, les credentials sont injectees dans la variable `VCAP_SERVICES` :

```json
{
  "VCAP_SERVICES": {
    "p-mysql": [{
      "name": "my-db",
      "credentials": {
        "hostname": "mysql.service.internal",
        "port": 3306,
        "username": "app-user",
        "password": "auto-generated",
        "uri": "mysql://app-user:pwd@mysql:3306/mydb"
      }
    }]
  }
}
```

Spring Boot detecte automatiquement ces credentials via le Spring Cloud Connectors ou java-cfenv.

### 9.5 Deploiements zero-downtime

#### Blue-Green

```bash
# 1. Deployer la nouvelle version sous un nom temporaire
cf push my-app-new -f manifest.yml

# 2. Mapper la route de production vers la nouvelle app
cf map-route my-app-new example.com --hostname my-api

# 3. Verifier que la nouvelle version repond correctement
curl https://my-api.example.com/health

# 4. Demapper la route de l'ancienne version
cf unmap-route my-app example.com --hostname my-api

# 5. Supprimer l'ancienne version
cf delete my-app -f
cf rename my-app-new my-app
```

#### Rolling Deployment

```bash
# Une instance a la fois (defaut max-in-flight=1)
cf push my-app --strategy rolling

# Avec un max-in-flight de 3
cf push my-app --strategy rolling --max-in-flight 3
```

Remplace les instances une par une : monte les nouvelles, verifie le health check, descend les anciennes.

#### Canary Deployment

```bash
# Deploy canary : 1 instance de la nouvelle version, puis pause
cf push my-app --strategy canary

# Canary graduel : d'abord 5%, puis 10%, puis 20%
cf push my-app --strategy canary --instance-steps 5,10,20

# Apres verification, continuer le deploiement
cf continue-deployment my-app

# Ou annuler
cf cancel-deployment my-app
```

### 9.6 Routes et domaines

| Type de domaine | Portee | Exemple |
|----------------|--------|---------|
| **Shared domain** | Toute la foundation | `apps.example.com` |
| **Private domain** | Une org (partageable) | `mycompany.com` |
| **Internal domain** | Communication interne (pas de traffic externe) | `apps.internal` |

```bash
# Creer un domaine prive
cf create-private-domain my-org mycompany.com

# Creer un domaine interne
cf create-shared-domain apps.internal --internal

# Route avec path
cf map-route my-app example.com --hostname api --path /v2

# Route TCP
cf create-route my-space tcp.example.com --random-port
```

---

## 10. Operations

### 10.1 Tanzu Operations Manager (Ops Manager)

Interface graphique et API pour installer, configurer et gerer les **tiles** (produits).

#### Workflow d'installation d'un tile

```
1. Telecharger le tile (.pivotal) depuis Broadcom Support Portal
2. Importer dans Ops Manager (UI ou API)
3. Configurer le tile (reseaux, AZ, ressources, proprietes)
4. Assigner un stemcell
5. Review Pending Changes
6. Apply Changes (BOSH deploy)
```

#### Commandes Ops Manager API

```bash
# Authentification
export OM_TARGET=https://opsman.example.com
export OM_USERNAME=admin
export OM_PASSWORD=<password>

# Lister les produits installes
om staged-products

# Telecharger un stemcell
om download-product --pivnet-api-token=<token> --product-slug=stemcells-ubuntu-jammy

# Appliquer les changements
om apply-changes

# Exporter l'installation
om export-installation --output-file installation.zip
```

### 10.2 Gestion des certificats

#### CredHub Maestro

Outil integre a Ops Manager pour la rotation automatique des certificats.

```bash
# Lister les certificats expirant bientot
credhub find -p /bosh-director | grep certificate

# Regenerer un certificat leaf
credhub regenerate -n /bosh-director/cf/router-ssl

# Rotation via Ops Manager API
# Dans Ops Manager 3.0.17+, case a cocher pour rotation automatique du CA BOSH DNS
```

#### Types de certificats

| Type | Gere par | Rotation |
|------|---------|----------|
| **CA root** | Ops Manager | Manuelle (procedure multi-etapes) |
| **CA intermediaire** | CredHub | Via CredHub Maestro |
| **Leaf certificates** | CredHub | Automatisable via Ops Manager (3.0+) |
| **Certificats configurables** | Operateur | Manuelle via Ops Manager UI |

### 10.3 Strategie LTS et upgrades

**Principe** : petites mises a jour frequentes pour minimiser les risques.

```
Chemin d'upgrade recommande :
  TAS 6.0.x (LTS) -> TPCF 10.0.x -> TPCF 10.2.x -> EAR 10.3.x

Jump upgrade :
  Versions anciennes -> directement vers une version LTS (Operations Manager 2.10+)
```

**Prerequis avant upgrade** :
1. Exporter l'installation (`om export-installation`)
2. Verifier la compatibilite des stemcells
3. Verifier les breaking changes dans les release notes
4. Lancer les smoke tests
5. Mettre a jour les buildpacks
6. Planifier un creneaux de maintenance

---

## 11. Composants et services de la plateforme

### 11.1 Foundation Core 3.0 / 3.1

Foundation Core permet de gerer la foundation et voir sa sante en un seul endroit, integre a Tanzu Operations Manager.

| Version | Changements cles |
|---------|-----------------|
| **3.0.32+LTS-T** | Version LTS. Vue sante de la foundation, switch entre UI Foundation Core et UI classique Ops Manager. |
| **3.1.6** | Integration avec Ops Manager 3.2.x, metriques beta, ameliorations UX. |

### 11.2 Elastic Application Runtime (EAR)

Anciennement Tanzu Application Service (TAS) puis Tanzu Platform for Cloud Foundry (TPCF).

| Version | RabbitMQ Mapping | Changements majeurs |
|---------|-----------------|-------------------|
| **4.0.27+LTS-T** (EAR) | anciennement TAS 4.0 | Version LTS. Derniere version avant le rebranding TPCF. |
| **6.0.24+LTS-T** (EAR) | anciennement TAS 6.0 | Version LTS courante. Support Ubuntu Jammy, cflinuxfs4. |
| **10.0** (TPCF) | Premier rebrand | Tanzu cf CLI v10, Puma pour Cloud Controller, licence obligatoire. |
| **10.2** (TPCF) | | Puma pour CC (multi-CPU), Registry credentials (space/org/foundation), cf CLI v10.2 seul supporte. |
| **10.3** (EAR) | Premier sous le nom EAR | OpenTelemetry Collector OTLP (port 9564), registry credentials, deploiement rolling avec scale params. |

### 11.3 Spring Cloud Gateway (API Gateway)

| Version | Compatible avec |
|---------|----------------|
| **2.1.7** | TAS 2.x - 4.x |
| **2.3.6** | TPCF 10.0-10.2, Ops Manager 3.0-3.1 |
| **2.4.1** | EAR 10.3+ |

**Fonctionnalites** :
- Routage dynamique des APIs
- **SSO** : integration avec UAA via plans SSO dedies, filtres commercial SSO
- **Rate Limiting** : configurable par route. Backend : Hazelcast (defaut) ou Redis/Valkey
- **Circuit Breaker** : resilience integree (Spring Cloud Circuit Breaker)
- **mTLS** : support natif
- **Haute disponibilite** : multiples instances Gateway

**Configuration** :
```bash
# Creer une instance
cf create-service spring-cloud-gateway standard my-gateway

# Binder une app
cf bind-service my-api my-gateway -c '{"routes": [{"path": "/api/**"}]}'
```

**Rate Limiting avec Redis** :
Le Lua Scripting doit etre active sur la tile Redis/Valkey, sinon le rate limiting echoue.

**Ressources par instance** : 1 GB memoire + 1 GB CPU.

### 11.4 App Metrics 2.2 / 2.3

Affiche jusqu'a 6 semaines de logs, metriques et events des apps.

| Version | Changements |
|---------|------------|
| **2.2** | Base : dashboards, alerting, integration Metric Store |
| **2.3** | Log Store avec PromQL-style label selectors, stockage InfluxDB, multi-tenant |

**Fonctionnalites** :
- Dashboards de performance applicative
- Indicator Documents (YAML) pour definir les indicateurs a surveiller
- Integration avec Metric Store et Log Cache
- Query directe via PromQL

### 11.5 Application Services (Spring Cloud Services)

| Version | Changements |
|---------|------------|
| **3.2.6** | Spring Boot 3.1.x, Spring Cloud 2022.0.x, stemcell Jammy, Config Server default label `main` au lieu de `master`, TLS NATS endpoint |
| **3.2.11** | Patches securite, corrections errands upgrade |
| **3.3.x** | Version courante |

**Sous-services inclus** :

| Service | Description |
|---------|------------|
| **Config Server** | Configuration centralisee (Git-backed) |
| **Service Registry** | Service discovery (Eureka) |
| **Spring Cloud Gateway** | API Gateway (cf section dediee) |

### 11.6 CyberArk Conjur Service Broker 1.4.2

Integre CyberArk Conjur pour la gestion de secrets dans les apps Cloud Foundry.

**Architecture** :
```
CF App → Conjur Buildpack (Summon binary) → Conjur Enterprise
  |
  +-- Binding ID = identite unique de l'app dans Conjur
  +-- Secrets injectes comme variables d'environnement au runtime
```

**Fonctionnement** :
1. Le Service Broker cree automatiquement des branches de policy Conjur mirrorant la structure org/space
2. Chaque space a sa propre instance de service
3. Au bind, l'app recoit une identite hote dans Conjur
4. Au runtime, Summon (Go binary) recupere les secrets et les injecte dans l'environnement

```bash
cf create-service cyberark-conjur community my-conjur
cf bind-service my-app my-conjur
```

### 11.7 Dynatrace Service Broker 2.0.1

**Deux modes d'integration** :

| Mode | Description |
|------|------------|
| **Service Broker** | Expose Dynatrace comme service dans le Marketplace. Apps bindees recoivent l'agent via le buildpack. |
| **Full-Stack Add-on** | BOSH add-on qui installe OneAgent sur TOUTES les VMs de la foundation (infrastructure + apps). |

**Buildpack Dynatrace** :
```yaml
# manifest.yml
buildpacks:
  - dynatrace_oneagent_buildpack   # en premier !
  - java_buildpack_offline
```

Le buildpack injecte le Dynatrace OneAgent dans l'app. Supporte : Java, .NET, Go, Node.js, PHP, Python, nginx, Apache.

Configure `$LD_PRELOAD` pour charger la librairie OneAgent.

```bash
# Via le marketplace
cf create-service dynatrace standard my-dynatrace
cf bind-service my-app my-dynatrace
```

**Compatibilite** : le support Dynatrace pour TAS peut etre en retard sur les releases VMware pour permettre les tests.

### 11.8 Healthwatch 2.3.0 / 2.3.4

Monitoring de sante de la plateforme basee sur Prometheus + Grafana.

**Architecture** :
```
Foundations (1..N)
  +-- Healthwatch Exporter (sur chaque foundation)
        |
        v
Healthwatch Tile (central)
  +-- Prometheus (scrape + stockage + alertes)
  +-- Grafana (dashboards)
  +-- Alertmanager (notifications)
```

**Categories de KPIs** :

| Categorie | Metriques surveillees |
|-----------|---------------------|
| **BOSH SLIs** | Sante du Director, duree des deploys, succes des taches |
| **TAS SLIs** | Succes des commandes cf (push, login, start, stop, delete) |
| **Diego** | Synchronisation, capacite memoire/disque disponible |
| **Certificats** | Expiration des certificats SSL (secondes avant expiration) |
| **Throughput** | Debit de messages, taux de perte de logs (1min, 1h) |
| **Canary (Blackbox)** | DNS lookup, codes HTTP, TLS, ICMP |

**Alerting** :
```yaml
# Configuration Alertmanager dans Healthwatch
receivers:
  - email
  - PagerDuty
  - Slack

# Les seuils sont a definir selon vos SLOs
# Status binaire : 0 = echec, 1 = succes
```

### 11.9 Metric Store 1.6.1 / 1.8.1

Couche de stockage persistant pour les metriques Loggregator.

**Caracteristiques** :
- **PromQL** : compatible Prometheus Query Language et API endpoints
- **InfluxDB** : moteur de stockage avec compression et index memoire-efficient
- **Multi-tenant** : auth proxy garantit que les devs n'accedent qu'a leurs metriques
- **Grafana** : fonctionne directement avec Metric Store sans traduction

**Limitation** : le scaling horizontal entraine une perte de donnees. Ne pas scaler horizontalement.

**Usage officiel** : App Metrics v2.3 et Apps Manager de TAS 2.9+.

```bash
# Query PromQL via cf CLI plugin
cf query 'http_requests_total{source_id="APP-GUID"}[5m]'
cf query 'rate(http_requests_total{source_id="APP-GUID"}[5m])'
```

### 11.10 Scheduler 2.0.9 / 2.0.23

Planification de taches (jobs) pour les apps Cloud Foundry.

**Types de taches** :
- **Jobs** : execution de Diego Tasks (ex : migration DB, batch)
- **Calls** : execution de requetes HTTP sortantes

**Expression cron** : format Quartz (MIN HOUR DAY-OF-MONTH MONTH DAY-OF-WEEK). Pas de secondes ni d'annees.

```bash
# Creer une instance
cf create-service scheduler-for-pcf standard my-scheduler
cf bind-service my-app my-scheduler

# Creer un job
cf create-job my-app my-job "rake db:migrate"

# Planifier (tous les jours a 2h du matin, timezone Europe/Paris)
cf schedule-job my-job "0 2 * * ?" --timezone "Europe/Paris"

# Executer ad hoc
cf run-job my-job

# Voir l'historique
cf job-history my-job
```

**Prerequis v2.0** :
- Stemcell Jammy (pas Xenial)
- MySQL 8.0
- Java Buildpack v4.42+

### 11.11 Spring Cloud Data Flow 1.14.7 / 1.14.10

Orchestration de stream processing et batch processing.

**Architecture** :
```
SCDF Server (deploye comme app CF)
  |
  +-- Stream : Source -> Processor -> Sink (via RabbitMQ ou Kafka)
  +-- Batch : Job avec Steps (reader -> processor -> writer)
```

**Dependances** :
- MySQL (ou autre SGBD relationnel)
- RabbitMQ ou Kafka
- Java Buildpack 3.8+

**v1.14 nouveautes** :
- Support Spring Batch 5.x
- Integration Wavefront pour monitoring
- Types reader/writer : File, AMQP, JDBC, Kafka

```bash
cf create-service p.data-flow standard my-dataflow
```

### 11.12 Tanzu for MySQL 3.3.0 / 10.1.0

Service MySQL manage en on-demand.

| Version | Changements |
|---------|------------|
| **3.3.0** | Stemcell Jammy, backups 8x plus rapides, artefacts 13% plus petits |
| **10.1.0** | Aligne sur le versionnement Elastic Application Runtime |

**Topologies** :

| Topologie | Noeuds | Usage |
|-----------|--------|-------|
| **Single node** | 1 | Dev/test |
| **Leader-follower** | 2 | Pre-production |
| **HA cluster** | 3+ | Production (Percona XtraDB Cluster / Galera) |

```bash
cf create-service p.mysql db-small my-db
cf create-service p.mysql db-ha-large my-ha-db   # HA
cf bind-service my-app my-db
```

### 11.13 Tanzu for Valkey 3.4.0

Anciennement Redis for VMware Tanzu Application Service. Valkey est un fork Redis-compatible.

**Plans de service** :

| Plan | Description |
|------|------------|
| **On-Demand** | VM dediee par instance Valkey. Jusqu'a 3 plans configurables (taille memoire, quotas). |
| **Shared-VM** | Plusieurs instances Valkey dans une seule VM. Economique pour dev/test. |

**Structures de donnees** : strings, lists, hashes, sets, sorted sets, bitmaps, HyperLogLogs, geospatial indexes.

```bash
cf create-service p.redis on-demand-cache my-cache
cf bind-service my-app my-cache
```

---

## 12. Monitoring et observabilite

### 12.1 Stack d'observabilite

```
Apps                    Plateforme
  |                        |
  v                        v
Loggregator          BOSH Health Monitor
  |                        |
  +----> Log Cache         +----> Healthwatch Exporter
  +----> Metric Store             |
  +----> Syslog Drain       Healthwatch (Prometheus + Grafana)
  +----> Nozzles                  |
           |                      +----> Alertmanager
           v                             |
     Dynatrace / Datadog /         Email, PagerDuty, Slack
     Splunk / ELK
```

### 12.2 Metriques Loggregator cles

```promql
# Taux de requetes HTTP par app
rate(http_total{source_id="APP-GUID"}[5m])

# Latence (percentile 95)
histogram_quantile(0.95, rate(http_duration_seconds_bucket{source_id="APP-GUID"}[5m]))

# Utilisation CPU
cpu{source_id="APP-GUID"}

# Utilisation memoire
memory_bytes_quota{source_id="APP-GUID"}
memory{source_id="APP-GUID"}
```

### 12.3 Dynatrace integration complete

```
Mode 1 : Buildpack (par app)
  App + Dynatrace Buildpack --> OneAgent injecte --> Metriques + Traces

Mode 2 : Full-Stack Add-on (toute la foundation)
  BOSH Add-on --> OneAgent sur chaque VM --> Infrastructure + Apps

Mode 3 : Service Broker (marketplace)
  cf create-service dynatrace --> cf bind-service --> Agent via VCAP_SERVICES
```

### 12.4 Dashboard Healthwatch

KPIs principaux a surveiller :

| KPI | Seuil recommande | Action |
|-----|-----------------|--------|
| Diego Cell Memory Available | > 20% | Ajouter des cells si < 20% |
| Diego Cell Disk Available | > 20% | Ajouter des cells ou nettoyer |
| cf push success rate | > 99% | Investiguer CC, Diego, buildpacks |
| Gorouter latency p99 | < 200ms | Verifier le scaling des routers |
| Certificate expiration | > 30 jours | Planifier la rotation |
| Log loss rate (1h) | < 1% | Scaler les Dopplers |
| BOSH deploy success | > 99% | Verifier le Director et l'IaaS |

---

## 13. Securite

### 13.1 Isolation Segments

Pools dedies de Diego Cells pour isoler les workloads.

```
Foundation
  +-- Isolation Segment "shared" (defaut)
  |     +-- Diego Cell 1, 2, 3
  |     +-- Gorouter shared
  |
  +-- Isolation Segment "pci"
  |     +-- Diego Cell 4, 5, 6  (reseau dedie)
  |     +-- Gorouter PCI (sous-reseau dedie)
  |
  +-- Isolation Segment "dmz"
        +-- Diego Cell 7, 8
        +-- Gorouter DMZ
```

```bash
# Creer un isolation segment
cf create-isolation-segment pci

# Assigner a une org
cf enable-org-isolation my-org pci

# Definir comme defaut pour un space
cf set-space-isolation-segment my-org/prod pci
```

**Reseau** :
- Chaque isolation segment doit avoir son propre sous-reseau
- Regles firewall specifiques pour le trafic ingress/egress
- Les Gorouters d'un segment ne routent que vers les cells de ce segment

### 13.2 Container-to-Container Networking

Reseau overlay entre conteneurs, non routable depuis l'exterieur.

```bash
# Autoriser app-frontend a appeler app-backend sur le port 8080
cf add-network-policy app-frontend app-backend --port 8080 --protocol tcp

# Lister les policies
cf network-policies

# Supprimer une policy
cf remove-network-policy app-frontend app-backend --port 8080 --protocol tcp
```

Supporte TCP et UDP. Les policies s'appliquent immediatement sans restart.

### 13.3 Application Security Groups (ASG)

Regles d'egress qui controlent les connexions sortantes des conteneurs.

```json
[
  {
    "protocol": "tcp",
    "destination": "10.0.0.0/8",
    "ports": "3306,5432",
    "description": "Allow MySQL and PostgreSQL in private network"
  },
  {
    "protocol": "tcp",
    "destination": "0.0.0.0/0",
    "ports": "443",
    "description": "Allow HTTPS to internet"
  }
]
```

**Types** :
- **Staging ASG** : appliquees pendant le staging (plus permissives pour telecharger les deps)
- **Running ASG** : appliquees a runtime (plus restrictives)

**ASGs par defaut** : `public_networks` et `dns`

```bash
# Creer un ASG
cf create-security-group my-asg rules.json

# Binder globalement (tous les spaces, en running)
cf bind-running-security-group my-asg

# Binder a un space specifique
cf bind-security-group my-asg my-org my-space --lifecycle running

# Lister
cf security-groups
```

### 13.4 CredHub

Gestion centralisee des credentials.

**Types de credentials** :

| Type | Contenu |
|------|---------|
| `password` | Chaine generee automatiquement |
| `certificate` | CA + certificat + cle privee |
| `rsa` | Paire de cles RSA |
| `ssh` | Paire de cles SSH |
| `user` | Username + password |
| `json` | Bloc JSON arbitraire |
| `value` | Valeur simple |

```bash
# Se connecter a CredHub
credhub login -s https://credhub.service.cf.internal:8844 --client-name=credhub-admin --client-secret=<secret>

# Generer un password
credhub generate -t password -n /bosh-director/cf/my-password

# Generer un certificat
credhub generate -t certificate -n /bosh-director/cf/my-cert \
  --common-name "my-service.internal" \
  --ca /bosh-director/cf/my-ca

# Lire une credential
credhub get -n /bosh-director/cf/my-password

# Rotation : regenerer
credhub regenerate -n /bosh-director/cf/my-cert

# Lister
credhub find -p /bosh-director/cf/
```

### 13.5 Conjur Integration (detail)

```
                    +-------------------+
                    | CyberArk Conjur   |
                    | Enterprise/Cloud  |
                    +---------+---------+
                              |
                    +---------v---------+
                    | Conjur Service    |
                    | Broker (tile)     |
                    +---------+---------+
                              |
              +---------------+---------------+
              |                               |
    +---------v---------+           +---------v---------+
    | Org: my-org       |           | Org: other-org    |
    | +-- Space: dev    |           | +-- Space: prod   |
    |      +-- App 1    |           |      +-- App 3    |
    |      +-- App 2    |           |                   |
    +-------------------+           +-------------------+
```

Le broker cree des branches de policy Conjur mirrorant l'arbre org/space. Les entitlements sont assignes au niveau org ou space.

---

## 14. Versions deployees -- Matrice de compatibilite

Exemple d'une foundation type :

| Produit | Version LTS | Version courante | Notes |
|---------|-------------|------------------|-------|
| Foundation Core | 3.0.32+LTS-T | 3.1.6 | |
| EAR (Linux) | 6.0.24+LTS-T | 10.3.x | Rebranding TAS -> TPCF -> EAR |
| EAR (anciennement TPCF) | 4.0.27+LTS-T | 10.3.x | |
| API Gateway | 2.1.7 | 2.4.1 | Spring Cloud Gateway |
| App Metrics | 2.2.2 | 2.3.2 | |
| Application Services | 3.2.6 | 3.2.11 | Spring Cloud Services |
| CyberArk Conjur | - | 1.4.2 | |
| Dynatrace Service Broker | - | 2.0.1 | |
| Healthwatch | 2.3.0 | 2.3.4 | Prometheus + Grafana |
| Metric Store | 1.6.1 | 1.8.1 | PromQL + InfluxDB |
| Scheduler | 2.0.9 | 2.0.23 | |
| Spring Cloud Data Flow | 1.14.7 | 1.14.10 | |
| Tanzu for MySQL | 3.3.0 | 10.1.0 | |
| Tanzu for Valkey | - | 3.4.0 | ex-Redis for TAS |
| Tanzu RabbitMQ | 2.4.1 | 2.4.3 | Voir skill rabbitmq |

---

## 15. Troubleshooting rapide

### App qui ne demarre pas

```bash
cf logs my-app --recent                   # Chercher les erreurs de staging/start
cf events my-app                          # Evenements (OOM, crash, etc.)
cf ssh my-app -c "cat /app/BOOT-INF/classes/application.yml"  # Verifier la config
cf env my-app                             # Verifier VCAP_SERVICES et env vars
```

### Problemes de route

```bash
cf routes | grep my-app                   # Verifier les routes mappees
cf curl /v3/routes?hosts=my-hostname      # API directe
# Verifier que l'app a des instances running
cf app my-app
```

### Problemes BOSH

```bash
bosh -e my-env -d cf vms --vitals        # Etat des VMs avec CPU/mem/disk
bosh -e my-env -d cf instances --failing  # Instances en echec
bosh -e my-env -d cf cloud-check          # Detection + reparation automatique
bosh -e my-env tasks --recent=10          # Taches recentes (erreurs ?)
```

### Problemes de certificat

```bash
# Via Ops Manager
om certificate-authorities
om expiring-certificates --expires-within 30d

# Via CredHub
credhub find -p /bosh-director/ | grep certificate
credhub get -n /bosh-director/cf/router-ssl -j | jq '.value.certificate' | openssl x509 -noout -enddate
```

---

Sources :
- [Tanzu Platform for Cloud Foundry Overview](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/10-2/eart/concepts-overview.html)
- [Diego Architecture](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/diego-diego-architecture.html)
- [Cloud Foundry Diego Architecture](https://docs.cloudfoundry.org/concepts/diego/diego-architecture.html)
- [HTTP Routing](https://docs.cloudfoundry.org/concepts/http-routing.html)
- [Cloud Foundry Routing Architecture](https://docs.cloudfoundry.org/concepts/cf-routing-architecture.html)
- [UAA Overview](https://docs.cloudfoundry.org/concepts/architecture/uaa.html)
- [Identity Providers in UAA](https://docs.cloudfoundry.org/uaa/identity-providers.html)
- [Loggregator Architecture](https://docs.cloudfoundry.org/loggregator/architecture.html)
- [Cloud Controller](https://docs.cloudfoundry.org/concepts/architecture/cloud-controller.html)
- [Orgs, Spaces, Roles](https://docs.cloudfoundry.org/concepts/roles.html)
- [App Manifest Attributes](https://docs.cloudfoundry.org/devguide/deploy-apps/manifest-attributes.html)
- [Deploying with Manifests](https://docs.cloudfoundry.org/devguide/deploy-apps/manifest.html)
- [Rolling Deployments](https://docs.cloudfoundry.org/devguide/deploy-apps/rolling-deploy.html)
- [Blue-Green Deployment](https://docs.cloudfoundry.org/devguide/deploy-apps/blue-green.html)
- [Service Brokers](https://docs.cloudfoundry.org/services/overview.html)
- [Open Service Broker API](https://www.openservicebrokerapi.org/)
- [Cloud Foundry Buildpacks](https://docs.cloudfoundry.org/buildpacks/)
- [Routes and Domains](https://docs.cloudfoundry.org/devguide/deploy-apps/routes-domains.html)
- [BOSH CLI Commands](https://bosh.io/docs/cli-v2/)
- [What is a Stemcell](https://bosh.io/docs/stemcell/)
- [CredHub](https://docs.cloudfoundry.org/credhub/)
- [Container-to-Container Networking](https://docs.cloudfoundry.org/concepts/understand-cf-networking.html)
- [App Security Groups](https://docs.cloudfoundry.org/concepts/asg.html)
- [Isolation Segments](https://docs.cloudfoundry.org/adminguide/isolation-segments.html)
- [Tanzu Operations Manager](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-operations-manager/3-0/tanzu-ops-manager/index.html)
- [Certificate Rotation](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-operations-manager/3-0/tanzu-ops-manager/security-pcf-infrastructure-api-cert-rotation.html)
- [Healthwatch](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/healthwatch-for-vmware-tanzu/2-3/healthwatch/index.html)
- [Metric Store](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/metric-store/1-8/metric-store-docs/index.html)
- [Scheduler](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/scheduler/2-0/sched/index.html)
- [Spring Cloud Gateway](https://techdocs.broadcom.com/us/en/vmware-tanzu/spring/api-gateway/2-3/apigateway/index.html)
- [Spring Cloud Data Flow](https://techdocs.broadcom.com/us/en/vmware-tanzu/spring/spring-cloud-data-flow-for-cloud-foundry/1-14/scdf-tanzu/index.html)
- [Tanzu for MySQL](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-mysql-tanzu-platform/3-3/mysql-tp/index.html)
- [Tanzu for Valkey](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-valkey-tanzu-platform/4-0/valkey-tp/index.html)
- [Dynatrace Service Broker](https://docs.vmware.com/en/Dynatrace-Service-Broker-for-VMware-Tanzu/services/dynatrace-service-broker-vmware-tanzu/index.html)
- [CyberArk Conjur Service Broker](https://docs.vmware.com/en/CyberArk-Conjur-Service-Broker-for-VMware-Tanzu/services/cyberark-conjur-service-broker-vmware-tanzu/index.html)
- [Application Services](https://techdocs.broadcom.com/us/en/vmware-tanzu/spring/application-services/3-2/appservices/index.html)
- [App Metrics](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/app-metrics/2-3/appmetrics/index.html)
- [EAR 10.3 Release Notes](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/10-3/eart/runtime-rn.html)

## References detaillees

- `guides/cf-cli-expert.md` — Référence expert cf CLI : tous les flags cf push, stratégies de déploiement (rolling/canary/blue-green), procédures de rollback (revisions, droplets, cancel), tunneling SSH base de données (MySQL/PostgreSQL/Oracle/Redis/RabbitMQ), tasks, restart vs restage, networking (C2C, ASG, isolation segments), permissions, cf curl API, feature flags, plugins, commandes d'urgence
