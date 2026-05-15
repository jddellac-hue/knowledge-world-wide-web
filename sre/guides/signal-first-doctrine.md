# Doctrine SRE — signal-first dashboarding à grande échelle

> Guide SRE portable (pas Dynatrace-spécifique). Cible : organisations avec +50 équipes, +500 SN, +1000 services à observer. La doctrine reste valable pour Grafana/Prometheus, Datadog, New Relic — seules les requêtes diffèrent.

## Le problème

Au-delà d'un seuil cognitif (~50 entités), un dashboard plat est inutilisable. Demander aux équipes de filtrer manuellement leur fanout (50, 200, 1000 services) ne marche pas — elles décrochent et l'observabilité régresse en informalité.

## Principe : afficher le signal, pas la donnée

Plutôt que de présenter N entités à filtrer, présenter **les K entités qui méritent attention maintenant**. Le filtrage est fait par la requête, pas par l'humain.

Trois mécanismes signal-first portables :

### 1. Top-K (heavy hitters)

Recette : `agréger | trier desc | limiter à K`. Variantes :
- Top 10 services par failure rate 24h.
- Top 10 endpoints par p95 latence 1h.
- Top 10 services qui se sont **le plus dégradés** en 24h (calcul delta `now() vs now()-24h`).

### 2. Anomaly-first

Lister **uniquement les entités flaggées par un détecteur** (Davis, alertmanager, anomaly detection) sur la fenêtre récente. La liste plate reste accessible en drill-down — mais l'écran d'accueil ne montre que ce qui est dégradé.

### 3. Burn-rate-first

Trier les entités par **% d'error budget consommé** sur 7j. Auto-priorisation : les services « plats mais cassés » remontent en haut tout seuls. Pratique parfait avec une couche SLO comme Pyrra ou Dynatrace SLO.

## Anti-patterns à proscrire

| Anti-pattern | Pourquoi c'est cassé |
|---|---|
| "1 dashboard par service" pour 1000 services | Personne ne maintient 1000 dashboards. Divergence + obsolescence garantie. |
| Liste plate triée alphabétiquement | Aucun signal informationnel. |
| Seuils statiques par service à la main | N services × 3 métriques = 3N seuils à mettre à jour. |
| Dashboard global avec 200 tuiles | Performance serveur dégradée, scroll humain. |
| 1 MZ / 1 segment par équipe RH | Réorgs cassent la structure. Toujours périmètre fonctionnel stable. |
| Dashboards créés à la main par chaque squad | Pas de cohérence, pas de hiérarchie, pas de réutilisation. |

## Patterns à industrialiser

| Pattern | Comment |
|---|---|
| Fanout par tag / segment | 1 template paramétré par `$team` ou `$sn`, instancié via URL params ou segment global |
| Top-K systématique | `sort … desc | limit 10|20|50` en place d'une liste plate |
| Honeycomb / heatmap pour les flottes | Visualise 100-1000 entités sans saturation |
| Calculated service metrics | Pré-agrégation côté plateforme, moins coûteux que requête à la volée |
| Hiérarchie de nommage | `<env>.<tribe>.<app>.<service>` → filtres `startsWith` cheap |
| Dashboard-as-code (Monaco / Terraform / Jsonnet) | Manifest central → CI génère N dashboards |

## Hiérarchie de dashboards à 5 niveaux

| Niveau | Audience | Contenu | Volume max |
|---|---|---|---|
| L1 DSI / COMEX | Direction | KPIs business, # incidents critiques, € à risque | <10 tuiles |
| L2 Chaîne de valeur / CUJ | PO, biz | Funnel parcours client, SLO consolidé par CUJ | 1/CUJ |
| L3 Équipe | Tech lead, SRE | Top-K dégradés, burn rate, problems Davis | 1 filtré par `team:` |
| L4 SN / produit | Squad | Topologie, dépendances, SLO par service | 1/SN généré |
| L5 Service / endpoint | Dev | Trace exemplars, top endpoints latence, code-level | drill-down |

**Règle de descente** : on descend uniquement si signal au-dessus. L5 n'est jamais lu en routine — c'est un dashboard de debug ouvert depuis un lien.

## Pattern « Pyramide de signaux »

Sans nom officiel dans la doc d'aucun vendeur, mais structurant : chaque niveau de la hiérarchie ne montre que **les signaux agrégés du niveau inférieur** (top-K, anomaly-first, burn-rate-first), jamais la liste plate. La descente est déclenchée par le signal, pas par exploration manuelle.

Conséquence : la lecture d'une plateforme à +1000 SN se fait en 30 secondes (L1 → signal → drill L2 → drill L3 …), pas en exploration des sous-pages.

## Audiences et dashboards signature

### Dev : "Mon service vient-il de casser ?"
- Top 20 traces les plus lentes des 30 dernières minutes (lien code-level).
- Diff deploy : error rate / latence p95 superposée à la timeline des deploys.
- Logs corrélés (DQL ou LogQL ou Loki).
- Cible : 1 dev, 1 service, 1 commit.

### Ops/SRE : "Que dois-je regarder MAINTENANT ?"
- Problèmes actifs (Davis/Alertmanager) triés par business impact.
- Burn rate top-10.
- RUM live / utilisateurs réels impactés.
- Pas de courbes longues séries — uniquement ce qui clignote rouge.

### Métier : "Le client passe-t-il ?"
- Business events funnel `commande → paiement → confirmation`.
- KPI : « x€ de transactions en risque ».
- Pas de mention de service, ni de host. Étapes de parcours uniquement.

## Mesure de réussite

| KPI | Cible |
|---|---|
| # tickets "créez-moi un dashboard" | 0 (parce que dashboard-as-code) |
| # dashboards manuels par squad | ≤ 2 |
| % SN avec dashboard L3 généré | ≥ 95% |
| % alertes en burn-rate (vs static) | ≥ 80% |
| Temps lecture d'un état SN (L1 → L4) | < 1 min |
| % SLO violations détectées avant impact | ≥ 70% |

## Ressources

- [📖1] Brendan Gregg — [The USE Method](https://www.brendangregg.com/usemethod.html)
- [📖2] Tom Wilkie — [The RED Method (Grafana Labs)](https://grafana.com/blog/the-red-method-how-to-instrument-your-services/)
- [📖3] Google SRE Book — [Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/) (4 Golden Signals)
- [📖4] Google SRE Workbook — [Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/) (burn rate multi-window)
- [📖5] Nobl9 — [SLO Metrics: A Best Practices Guide](https://www.nobl9.com/service-level-objectives/slo-metrics)
- [📖6] Pyrra — [SLO monitoring for Prometheus](https://pyrra.dev/)
- Cross-ref : [`../guides/dashboards-audiences.md`](dashboards-audiences.md), [`../guides/llm-as-sre-advisor.md`](llm-as-sre-advisor.md), [`../../dynatrace/experience/dashboards-scale.md`](../../dynatrace/experience/dashboards-scale.md)
