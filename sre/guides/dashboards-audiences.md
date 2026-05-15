# Guide SRE — Dashboards par audience (dev / ops / métier)

> Guide portable. Compatible Dynatrace, Grafana, Datadog. Décrit *quoi mettre* dans chaque dashboard et *à qui* il s'adresse, pas *comment* l'implémenter techniquement.

## Pourquoi séparer les audiences

Un dashboard unique pour tout le monde = un dashboard que personne ne lit.

Trois audiences avec besoins radicalement différents :

| Audience | Question typique | Cadence de regard |
|---|---|---|
| Dev | « Mon dernier déploiement a-t-il cassé quelque chose ? » | sur événement (deploy, alerte) |
| Ops / SRE | « Que dois-je regarder maintenant ? » | continu, 24/7 |
| Métier / Biz | « Le client passe-t-il ? » | quotidien, dashboard de pilotage |

Une même métrique technique (par ex. latence p95) sert ces trois audiences différemment : pour le dev, c'est un signal de régression post-deploy ; pour l'ops, c'est un déclencheur d'investigation ; pour le métier, c'est invisible — ce qui compte c'est *le client passe ou pas*.

## Dashboard "dev" — orienté code & deploy

### Question
« Mon service vient-il de casser ? Ai-je une régression depuis le dernier deploy ? »

### Contenu signature
1. **Top traces lentes** sur les 30 dernières minutes, avec **lien code-level** (distributed tracing → fichier:ligne).
2. **Diff deploy** : courbe error rate et p95 latence superposée à la **timeline des déploiements** (event overlay).
3. **Logs corrélés** : 50 derniers logs ERROR du service.
4. **Exceptions** : top types d'exception sur 1h.
5. **Performance par endpoint** : top 10 endpoints par latence p95 (drill-down vers traces).

### Granularité
1 dev, 1 service, 1 commit. Pas de vue globale, pas d'autres services que ceux qu'on possède.

### Période
Court : 30 min à 6h. Au-delà, c'est le dashboard ops qui prend le relais.

### Anti-patterns
- KPIs métier (le dev n'a pas l'unité).
- Vue de 10 services (le dev en possède 1-2).
- Latence p99 long terme (le dev veut p95 court terme).

## Dashboard "ops / SRE" — orienté incident

### Question
« Que dois-je regarder MAINTENANT ? Qu'est-ce qui clignote rouge ? »

### Contenu signature
1. **Problèmes actifs** triés par business impact (Davis, Alertmanager).
2. **Burn rate top-10** : services qui flambent leur error budget en ce moment.
3. **RUM live** : nombre d'utilisateurs réels actuellement impactés.
4. **Saturation infrastructure** : top 5 hosts/clusters en zone rouge (CPU/mem/disk > seuil).
5. **Synthetic checks** rouges.

### Granularité
Filtre par équipe (`team:` tag) ou par criticité (`criticality:tier-1`). Pas de granularité service-par-service — c'est le job du dashboard dev en drill-down.

### Période
Live et 1h. Plus de courbes longues séries — uniquement ce qui clignote rouge.

### Anti-patterns
- Courbes 30 jours (rien d'actionnable).
- Métriques système sans contexte (pourcentage CPU sans le service).
- Listes plates de tous les services (illisible à +100 services).

## Dashboard "métier" — orienté business

### Question
« Le client passe-t-il ? Sommes-nous en train de perdre des transactions ? »

### Contenu signature
1. **Funnel CUJ** : `commande → paiement → confirmation` (taux de complétion à chaque étape).
2. **KPI principal** : nombre de transactions en risque, ou € à risque à cause des problèmes actifs.
3. **Conversion** : %  d'utilisateurs qui complètent le parcours, comparé à la baseline.
4. **Disponibilité par CUJ** : `cuj:<parcours>` à 99.5% / 99.95% / 99.99% — atteint ou pas.
5. **Top 5 problèmes business** détectés (Davis Business Events ou équivalent).

### Granularité
1 CUJ = 1 dashboard. Pas de service, pas de host, pas de pod — seulement des **étapes de parcours**.

### Période
24h pour le pilotage quotidien, 7-30j pour le pilotage hebdomadaire.

### Anti-patterns
- Latence p95 du service X (le métier ne sait pas ce qu'est X).
- Erreurs HTTP 500 (le métier veut "% commandes échouées", pas "erreurs serveur").
- Volume de logs (illisible).

## Règle "Don't mix audiences"

Un dashboard qui mélange dev + ops + biz = un dashboard que personne ne lit.

Si un PO demande "ajoutez la latence p95 du service X au dashboard métier" → refuser. Lui montrer à la place comment relier le SLO du CUJ au dashboard métier (le SLO encapsule la latence dans une mesure intelligible côté business).

Si un dev demande "ajoutez le funnel commande au dashboard service" → idem. Lui donner un lien vers le dashboard métier en cas d'incident pour qu'il voie l'impact downstream.

## Matrice signal-first par audience

| Audience | Top-K | Anomaly-first | Burn-rate-first |
|---|---|---|---|
| Dev | Top traces lentes | Davis problems sur mon service | n/a (trop court terme) |
| Ops | Top services dégradés | Davis problems actifs équipe | Top SLO consommés 7d |
| Métier | Top CUJ dégradés | n/a (trop technique) | Top CUJ en risque |

## Onboarding d'une nouvelle équipe SN

Étapes minimales pour qu'une équipe ait ses 3 dashboards :

1. **Tagging** : `team`, `sn`, `env`, `tier`, `cuj` posés sur les entités.
2. **Instanciation** : depuis le manifest central (`teams.yaml`), CI/CD pousse les 3 dashboards.
3. **Personnalisation L5** : la squad peut créer ses propres dashboards service-level si besoin, mais les L1-L4 restent générés.
4. **Démo** : 30 min de présentation à l'équipe par la plateforme SRE.

Critère de réussite : 0 ticket "créez-moi un dashboard".

## Ressources

- [📖1] Google SRE Book — [Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/) — chapitre 4 Golden Signals.
- [📖2] Honeycomb — [Observability for Business Stakeholders](https://www.honeycomb.io/blog/observability-business-stakeholders).
- [📖3] CNCF — [Observability TAG whitepapers](https://github.com/cncf/tag-observability/tree/main/whitepapers).
- Cross-ref : [`signal-first-doctrine.md`](signal-first-doctrine.md), [`../../dynatrace/experience/dashboards-scale.md`](../../dynatrace/experience/dashboards-scale.md).
