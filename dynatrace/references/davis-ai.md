# Davis AI — modes, baselines, RCA, CoPilot

> Référence interne. Source détaillée : [`03-davis-ai.md`](../03-davis-ai.md) (workdir local).

## Vue d'ensemble

Davis = **hypermodal AI** Dynatrace, 3 familles :

| Famille | Rôle | Déterminisme |
|---|---|---|
| **Causal AI** | RCA topology-aware via Smartscape | Déterministe |
| **Predictive AI** | Forecast, baselining, anomaly detection | Probabiliste reproductible |
| **Generative AI** | Davis CoPilot (LLM custom RAG, GA jan 2026) | Non déterministe |

Différence clé vs ML générique : Davis traverse un **graphe topologique** (Smartscape) plutôt que de corréler statistiquement N séries. Conséquence : aussi bon que le Smartscape — si une dépendance n'est pas instrumentée OneAgent, c'est un angle mort.

Tourne **par défaut sans configuration** sur les entités OneAgent. Pas d'enrôlement manuel par SN [📖1].

## Anomaly Detection — 4 modes [📖2][📖3]

### 1. Auto-adaptive threshold
Recalculé chaque jour à partir des 7 derniers jours.
- baseline = **p99** sur fenêtres 1 min
- variabilité = **IQR (Q75-Q25)**
- seuil = baseline + (n × IQR), n configurable

C'est **percentile + IQR**, pas sigma gaussien → robuste aux outliers.

### 2. Seasonal baseline
14 jours de mesures à la minute. Apprend les patterns récurrents (jour/nuit, semaine/weekend) [📖4]. Confidence band probabiliste, élargi par `tolerance`.

### 3. Static threshold
Limite dure manuelle. Indispensable quand on connaît la valeur critique (CPU>90%, free disk<5%, error_budget>X%).

### 4. Automated multidimensional baselining (défaut)
Appliqué auto sur les services pour `response.time` (p50+p90) et `failure.rate` [📖1]. Baselines séparées par dimension :
- User actions, géographie (continent→ville), browsers+versions, OS+versions.

C'est ce qui scale à +1000 SN sans configuration manuelle.

### Paramètres communs
- **Sliding window** : nb échantillons 1 min en violation (défaut 3/5).
- **De-alerting samples** : nb échantillons normaux pour fermer (défaut 5).
- **Alert condition** : above / below / outside.

## Adaptive baseline — cold start / dérive [📖1][📖5]

| Phase | Durée | Comportement |
|---|---|---|
| Bootstrap | 0 → 2h | Pas d'alerte |
| Baselines transitoires | 2h → 24h | Alertes possibles, peu fiables |
| Daily refresh | 24h → 7j | Recalcul quotidien. Failure rate démarre à 1.4j |
| Full pattern | > 7j | Saisonnalité hebdo complète |

**Forecast cube** : après 1 semaine, Davis prédit la suivante et compare.

**Risque connu** : workloads très dynamiques (K8s autoscaling) → baseline pollué, vraies anomalies masquées [📖6]. Recommandation officielle : **désactiver auto-baselining**, passer en static.

## Davis Forecast [📖7][📖8]

Prédit toute série temporelle numérique, datasets externes inclus.

**Cas validés** :
- Capacity management (disk/CPU/mem saturation prédite J+N).
- Predictive maintenance cloud disks via Workflow + AutomationEngine.
- Business forecasting (Black Friday).
- SLO burn rate forecasting [📖9].

**Limites** : préfère saisonnalité claire. Signal erratique → intervalle de confiance inexploitable.

## Root Cause Analysis topology-aware [📖10][📖11]

1. Davis détecte événement sur entité.
2. Traverse Smartscape (graphe causal déterministe).
3. Sur chaque voisin lié, analyse on-demand de change-points.
4. Fusionne événements convergents → **1 problème, pas N alertes**.

Exemple : frontend appelle 3 services, slowdown simultané → **1 seul problem** avec chaîne causale.

**Fenêtre de merging** : 90 min. Au-delà = nouveau problème distinct [📖12].

Pour +1000 SN, c'est ce qui évite l'alert storm — Davis dédoublonne via topologie, pas via grouping configuré.

## Davis CoPilot [📖13][📖14]

LLM custom Dynatrace (RAG, pas OpenAI direct), GA jan 2026.

**Capacités** :
- NL → DQL.
- DQL explanation.
- Problem summary + chaîne causale en NL.
- Exploratory analysis (dérives lentes invisibles aux seuils).
- MCP server pour Claude Code / GitHub Copilot [📖15].
- Workflows assist (gen blocs Workflow).

**Limites strictes** [📖12] :
- **25 req / 15 min / user**, **60 / 15 min / env**.
- Données client **pas utilisées** pour fine-tune.
- Non déterministe → jamais dans Workflows critiques automatisés.

**Use case fort en +1000 SN** : démocratiser la construction de dashboards/queries chez les équipes SN, plutôt que de centraliser chez les SRE.

## Matrice Davis vs static — quand quoi

| Cas | Mode | Pourquoi |
|---|---|---|
| Response time service | Auto-adaptive (défaut) | Scale gratuit |
| Failure rate service | Multidim baseline (défaut) | Géré nativement |
| SLO contractuel ferme | Static = threshold SLO | Ne pas laisser dériver |
| CPU/Mem host | Static 85/95% | Saturation, pas anomalie statistique |
| Free disk | Static + Forecast | Critique + anticipation |
| Traffic métier | Seasonal baseline | Saisonnalité forte |
| K8s autoscaling | Static / percentile fixe | Baseline pollué [📖6] |
| Métriques rares | Static | Pas assez de samples |
| Dérive lente (memory leak) | Static + Davis Exploratory | Adaptive *suit* la dérive |
| Détection stop / 0 | Static + alert missing data | Davis sait alerter sur absence |
| SLO burn rate | Static + Davis Forecast | Burn fixe, forecast pour anticiper |

**Règle générale** : Davis par défaut sur les 80% bruit, static codifié en IaC pour les 20% structurels via tag/MZ. **Ne configurer jamais manuellement +1000 SN**.

## Custom anomaly detection — setup [📖16][📖17]

Settings 2.0 → `builtin:anomaly-detection.metric-events`.

**Types** :
- Metric key events : sur 1 métrique + filtre entité.
- Metric selector events : sur résultat d'un metric selector DQL-like.

**Limites tenant** [📖12] :
- 1000 custom alert configs, 10 000 metric events, 100 000 dimensions monitorées.
- Auto-adaptive : 100 configs × 1000 dims.
- Seasonal : 100 × 500.
- Static : 100 × 1000.

**Workflow scale** :
1. Configs en IaC (Terraform/Monaco).
2. Cibler via MZ/tags (`env:prod AND team:<X>`).
3. Push API via CI/CD.
4. Preview alerting intégré (montre fired sur 7j avant publication).

## Limites & risques

### Faux positifs typiques
- Autoscaling K8s pollue le baseline.
- Déploiements fréquents = "anomalies".
- Sliding window trop court (3/5) sur spikes transitoires.
- Cold start < 7j.

### Faux négatifs / aveuglements
- Dérive lente (memory leak, latency creep) → adaptive **suit** la dérive.
- SLO drift → adaptive masque.
- Métier rare → trop peu de samples.
- Custom metrics non rattachées entité → pas de RCA.

### Limites quantitatives
- 10 000 problèmes actifs simultanés.
- 15 000 events actifs (4000/provider).
- 100 000 events/h (200 000 pour AVAILABILITY + METRIC_EVENTS).
- CoPilot 25 req/15 min/user.
- Problem merging window 90 min.

### Risques opérationnels
- CoPilot non déterministe → pas dans automation critique.
- Forecast sur erratique → bande de confiance inutile.
- Causal RCA = aussi bon que Smartscape.

## Recommandations pour +1000 SN

1. **Davis par défaut** sur le 80% bruit (response time, failure rate).
2. **Static codifié IaC** sur les 20% structurels (SLO, CPU/mem/disk, dérives lentes), appliqué via tag/MZ.
3. **Forecast** pour capacity planning.
4. **Davis Problems exposés via dashboards** + Problems API v2 vers PagerDuty/Slack.
5. **CoPilot** pour démocratiser, **pas pour automatiser des décisions**.
6. **Exploratory Analysis** pour les dérives lentes qu'aucun seuil ne verrait.

## Ressources

- [📖1] [Davis AI overview - Dynatrace Docs](https://docs.dynatrace.com/docs/discover-dynatrace/platform/davis-ai)
- [📖2] [Anomaly detection - Dynatrace Docs](https://docs.dynatrace.com/docs/discover-dynatrace/platform/davis-ai/anomaly-detection)
- [📖3] [Auto-adaptive thresholds - Dynatrace Docs](https://docs.dynatrace.com/docs/discover-dynatrace/platform/davis-ai/anomaly-detection/concepts/auto-adaptive-threshold)
- [📖4] [Seasonal baseline - Dynatrace Docs](https://docs.dynatrace.com/docs/discover-dynatrace/platform/davis-ai/ai-models/seasonal-baseline)
- [📖5] [Automated multi-dimensional baselining](https://docs.dynatrace.com/docs/discover-dynatrace/platform/davis-ai/anomaly-detection/concepts/automated-multidimensional-baselining)
- [📖6] [Troubleshooting Dynatrace in Enterprise DevOps - Mindful Chase](https://www.mindfulchase.com/explore/troubleshooting-tips/devops-tools/troubleshooting-dynatrace-in-enterprise-devops-advanced-diagnostics-and-fixes.html)
- [📖7] [Davis Forecast Analysis - Dynatrace Docs](https://docs.dynatrace.com/docs/discover-dynatrace/platform/davis-ai/ai-models/forecast-analysis)
- [📖8] [Forecast with Davis AI - Dynatrace Developer](https://developer.dynatrace.com/develop/forecast-with-davis-ai/)
- [📖9] [Dynatrace AI predicts SLO violations (blog)](https://www.dynatrace.com/news/blog/dynatrace-ai-predicts-slo-violations-and-pinpoints-root-causes-proactively/)
- [📖10] [Root cause analysis concepts - Dynatrace Docs](https://docs.dynatrace.com/docs/dynatrace-intelligence/root-cause-analysis/concepts)
- [📖11] [Event analysis and correlation](https://docs.dynatrace.com/docs/dynatrace-intelligence/root-cause-analysis/event-analysis-and-correlation)
- [📖12] [Davis AI limits - Dynatrace Docs](https://docs.dynatrace.com/docs/discover-dynatrace/platform/davis-ai/reference/davis-ai-limits)
- [📖13] [Announcing GA of Davis CoPilot](https://www.dynatrace.com/news/blog/announcing-general-availability-of-davis-copilot-your-new-ai-assistant/)
- [📖14] [Davis exploratory analysis](https://www.dynatrace.com/news/blog/davis-ai-exploratory-analysis/)
- [📖15] [Dynatrace MCP and GitHub Copilot (blog)](https://www.dynatrace.com/news/blog/sky-high-developer-productivity-with-dynatrace-mcp-and-github-copilot/)
- [📖16] [Metric events - Dynatrace Docs](https://docs.dynatrace.com/docs/dynatrace-intelligence/anomaly-detection/metric-events)
- [📖17] [Settings API metric events schema](https://docs.dynatrace.com/docs/dynatrace-api/environment-api/settings/schemas/builtin-anomaly-detection-metric-events)
