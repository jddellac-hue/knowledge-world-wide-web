# Expérience — Dashboards Dynatrace à grande échelle

> Leçons généralisables tirées d'une mise en œuvre Dynatrace pour +100 équipes / +1000 SN / +7000 services. Pas de noms réels.

## Le problème scale

Au-delà d'une masse critique d'entités monitorées, "1 dashboard par service filtré à la main" s'effondre. Seuils observés (doc + community) [📖1] :

- ~100 règles de tagging simples → cycle d'assignation **~1 min**. Plusieurs milliers de règles complexes → **plusieurs heures**.
- **Limite dure 5000 MZ / env**.
- Dashboard : avertissement explicite au-delà de **20 tuiles**, plafond **4000 datapoints par tuile** [📖2].
- Limite cognitive humaine : **~50 entités** affichées simultanément. Au-delà, on scrolle, on ne lit pas.

Doc Dynatrace explicite : *« in most cases, you don't want to see all available entities, which can easily go into tens of thousands. Typically, it's about identifying the heavy hitters »* [📖2].

**Conséquence** : passer de "afficher tout" à "afficher ce qui mérite attention".

## Signal-first : 3 patrons portables

### 1. Top-K (heavy hitters)

```dql
timeseries {failed=sum(dt.service.request.failure_count), total=sum(dt.service.request.count)},
  by:{dt.entity.service}, interval:24h
| fieldsAdd failure_rate = failed[]/total[]
| sort arrayAvg(failure_rate) desc
| limit 10
```
*« top 10 services par taux d'échec sur 24h ». L'utilisateur n'a rien à filtrer.*

### 2. Anomaly-first (Davis flagged only)

```dql
fetch events, from: now() - 24h
| filter event.kind == "DAVIS_PROBLEM"
| summarize lastStatus = takeLast(event.status), by: { event.id, affected_entity_ids, dt.owner }
| filter lastStatus == "ACTIVE"
| expand affected = affected_entity_ids
| summarize problems = count(), by: { dt.owner }
| sort problems desc
```
*Piège connu : `dt.davis.problems` émet plusieurs records par problème. Toujours `takeLast` après tri avant filter [📖3].*

### 3. Burn-rate-first

```dql
fetch dt.slo
| filter slo.target >= 99.5
| sort error_budget_consumed_7d desc
| limit 20
```
*Auto-priorisation par % budget consommé. Plus de N alertes par seuil à maintenir.*

**Règle d'or** : sur +1000 entités, JAMAIS de liste plate. Toujours `sort … desc | limit N`.

## Hiérarchie 5 niveaux

| Niveau | Audience | Contenu | Volume |
|---|---|---|---|
| L1 DSI | COMEX, Direction | KPIs business, # problems critiques, transactions risque | <10 tuiles |
| L2 CUJ | PO, biz | Funnel parcours client, SLO consolidé | 1/CUJ |
| L3 Équipe | Tech lead, SRE | Top-K dégradés, burn 7d, Davis problems team | filtré `team:` |
| L4 SN | Squad | Topologie SN, dépendances, SLO services | 1/SN généré |
| L5 Service | Dev | Trace exemplars, top endpoints, code-level | drill-down |

**Règle de descente** : on descend uniquement si signal au-dessus. L5 jamais accueil — dashboard de debug ouvert depuis lien.

## Multi-tenant by tag

**Pattern signature** : un seul dashboard, paramétré par `$team` ou `$sn` (variable DQL), qui re-segmente automatiquement le fanout.

1. Convention de tagging stricte (cf. `references/tagging-mz-topologie.md`) : `team:<x>`, `sn:<y>`, `tier:<z>`, `env:<w>`.
2. Variable dashboard *dynamic* alimentée par DQL : `fetch dt.entity.service | summarize by:{tags.team} | sort tags.team asc`.
3. Chaque tuile utilise `$team` dans son filtre.
4. **Même dashboard sert N équipes**, chacune voit son périmètre.

**Variante moderne** : **Segments** [📖4][📖5]. Au lieu d'une variable, on définit un segment réutilisable globalement, appliqué automatiquement à toutes les apps Dynatrace (Notebooks, Dashboards, SLO app, Problems app). Successeur officiel des MZ pour ce cas.

## Dashboard-as-code obligatoire

Sans dashboard-as-code, +100 équipes = +100 dashboards manuels divergents → ingérable.

**Pipeline-type** :
1. Manifest source unique (`teams.yaml`) : équipes, SN, services, CUJ.
2. 1 template par archétype (L1/L2/L3/L4/L5), versionné Git.
3. CI lit le manifest, instancie via Monaco ou Terraform `dynatrace_document`.
4. Push DEV → smoke → PROD.
5. PR sur `teams.yaml` = N dashboards générés.

**Anti-pattern critique** : Monaco/Terraform crée dashboards **privés par défaut**. Mettre `private = false` + sharing explicite dans template, sinon invisibles aux équipes [📖6].

## Anti-patterns à proscrire à l'échelle

1. **God dashboard global** charge 7000 services. Casse au-delà de 20 tuiles [📖2].
2. **MZ sur tout, pour tout le monde** : explosion combinatoire, plafond 5000. Migrer Segments [📖4].
3. **Alerting per-service threshold statique** : N services × 3 métriques = 3N seuils à maintenir. Davis baselines + burn rate suppriment ce travail.
4. **Listes plates tri alphabétique** : aucune valeur. Trier par signal `desc` + `limit`.
5. **Tagging rules avec traversées parent-enfant** : minutes → heures. Préférer naming hiérarchique + `beginsWith` [📖7].
6. **Trop de calculated service metrics** : 40+ par service = ingérable. DQL à la place [📖8].
7. **Dashboards créés à la main par squad** : pas de cohérence. Forcer Monaco/Terraform.

## Patterns scale recommandés

- **Fanout par tag/segment** > N copies.
- **Top-K systématique** : `sort … desc | limit 10|20|50`.
- **Honeycomb** pour vues flotte denses (100-1000 entités sans saturation).
- **Calculated service metrics** pour pré-agrégation (économise DDU et réactivité).
- **Hiérarchie d'entity names** `<env>.<tribe>.<app>.<service>` → `startsWith` performant.
- **OneAgent env tags** (`DT_TAGS`) > règles serveur quand possible.

## Études de cas publiques

- **TD Bank** [📖9] : 7 outils legacy éliminés, -45% licensing, transaction failure 0.16% → 0.06%.
- **Virgin Money** [📖10] : réorg autour des customer journeys, 15 mois → 3 mois.
- **Perform 2026** [📖11] : Dynatrace pivote sur Domain-Specific Agents → dashboards lus par humains deviennent secondaires.

**Leçon transversale** : les orgs qui réussissent passent du paradigme "service-centric" au paradigme "journey-centric". Et arrêtent de demander aux équipes de configurer leur monitoring service par service.

## Recommandations pour +100 équipes

1. **Standard de tagging d'ownership** comme prérequis d'onboarding (cf. `references/tagging-mz-topologie.md`).
2. **Bannir dashboards manuels par squad**. 4-5 archétypes générés par IaC.
3. **MZ → Segments** progressivement.
4. **Signal-first par défaut**. Liste plate jamais en écran d'accueil.
5. **Multi-window multi-burn-rate** sur SLO [📖12].
6. **Hiérarchie 5 niveaux** strict.
7. **Site Reliability Guardian** comme deploy gate [📖13].
8. **Investir dans données bien taggées + Grail bien structuré** > investir dans dashboards visuels (ère agentique).

**Pattern propriétaire** sans nom officiel dans la doc : **Pyramide de signaux** — chaque niveau hiérarchique ne montre que les signaux *agrégés* du niveau inférieur (top-K, anomaly-first, burn-rate-first), jamais la liste plate. La descente est déclenchée par le signal, pas par exploration manuelle.

## Patron structurel des dashboards *ready-made* Dynatrace (réutilisable)

Inspection des préfabriqués Dynatrace (apps Kubernetes / SLO / Databases / Digital Experience). Patron récurrent, par **famille de signal** :

```
markdown (titre de section)
→ bande de singleValue KPI (couleur conditionnelle = « voir vite » < 10 s)
→ areaChart « Top 20 <entité> » (signal-first, composition dans le temps)
→ table détail (valeur / requests / limits / throttle par entité)
→ markdown (séparateur → section suivante)
```

Mapping visualisation → usage (convention DT observée) :

| Besoin | Viz DT |
|---|---|
| Volume / débit composé par entité dans le temps | **`areaChart`** Top-K (pas lineChart) |
| KPI d'entrée « état en un coup d'œil » | **`singleValue`** + coloration conditionnelle |
| Détail multi-colonnes par entité | **`table`** (colonnes configurables, seuils) |
| Répartition catégorielle (codes, vendors) | **`categoricalBarChart`** / `pieChart` |
| Santé d'une flotte dense (100-1000 entités) | **`honeycomb`** |
| Distribution latence | `histogram` / heatmap |
| SLO / burn-rate | tuile native **`slo`** + `dt.davis.problems` + **Segments** (`$dt_filter_segments`) |
| RUM (Core Web Vitals LCP/INP/CLS) | `fetch user.events` — **famille séparée, jamais dans un dashboard service/RED** |

Autres conventions DT reprises : **commentaires `//` dans les requêtes** (pédagogie intégrée), **Top 20** comme cap Top-K par défaut, **markdown** comme séparateurs de section (zéro dépendance data → ne casse jamais). Le RED se lit **par service** ; les vues *workload/pod* relèvent de USE (méthode Gregg) → dashboard distinct, pas mélangé (cf. [`../../sre/guides/golden-signals.md`](../../sre/guides/golden-signals.md)).

> Réfs : préfabriqués Dynatrace (Hub apps) · [Dynatrace — Dashboards](https://docs.dynatrace.com/docs/analyze-explore-automate/dashboards-and-notebooks/dashboards-new) · [Table visualization](https://docs.dynatrace.com/docs/analyze-explore-automate/dashboards-and-notebooks/edit-visualizations/visualization-table) · [Segments (successeur MZ)](https://docs.dynatrace.com/docs/manage/segments/upgrade-guide-segments).

## Anti-pattern d'échelle : « les gros services écrasent les petits » + ton du board

Remarque terrain récurrente : à l'échelle, quelques entités à fort volume rendent un dashboard illisible (elles dominent toute échelle absolue). Doctrine portable :

- **Classer/colorer par écart vs le propre rythme habituel de l'entité** (baseline saisonnière), **jamais par taille absolue**. Gros + stable = discret ; petit + dévié = visible. C'est aussi ce qui rend le board *blameless* (on ne compare pas les entités entre elles).
- **Normaliser** (%, ratio, écart) en vue macro ; absolu seulement au drill.
- Viz qui ne sur-pondèrent pas la taille : `honeycomb` (état, pas surface), `singleValue`+**sparkline** (forme, pas magnitude), Top-K **par écart**.
- **Filtre de bruit saisonnier** : un rythme habituel (lent/fréquent/variable mais identique chaque H/J/S/M) doit rester **vert** — seul l'inhabituel est un signal. Cf. section baseline ci-dessous.
- **Ton** : vert par défaut (la majorité va bien) → board *rassurant qui donne envie d'être ouvert*, pas un mur rouge. Rouge rare et réservé au signal réel. Inviter (« à explorer ») plutôt qu'alarmer (« ALERTE/FAIL »). Lexique compris **et accepté** par toutes les audiences (dev/SRE/manager/on-call) : pas de « worst »/« fautif », infobulles sur tout terme technique.

Palette DT exhaustive (doc officielle, 22 types) : line/area/**band**/bar/**categoricalBar**/pie/donut/**honeycomb**/**histogram**/**heatmap**/**scatterplot**/**treemap**/**gauge**/**meterBar**/`singleValue`(+**sparkline**+seuils+couleur cond.)/`table`(+seuils)/choropleth·dot·bubble·connection map/`raw`/`recordList`/`markdown`/`slo` natif. Choisir **le rendu adapté au niveau de zoom** (macro = chiffre coloré+sparkline+honeycomb ; micro = lineChart percentiles+table+histogram). Réf : [Dynatrace — Edit visualizations](https://docs.dynatrace.com/docs/analyze-explore-automate/dashboards-and-notebooks/edit-visualizations).

## Baseline saisonnière : `shift:` n'accepte que des durées fixes — `28d` > `30d`

`timeseries … shift:-Nx` ne supporte **que des durées fixes** : `h`, `d` (jours, convertis en heures). **Non supporté** : `-1mo`/`-1M` (mois calendaire), `-4w` (semaines) → `Error` / `PARSE_ERROR` (vérifié tenant `vtu43544`).

Conséquence pour une comparaison « mois précédent » (filtre de bruit saisonnier) : utiliser **`-28d` (4×7 j), pas `-30d`**. La saisonnalité du trafic humain est **hebdomadaire** (motif par jour de semaine) : `28d` conserve le **même jour de semaine et la même heure** que « maintenant » ; `30d` décale de ~2 jours → on compare p.ex. un lundi à un samedi → **faux signal**. De même `7d` (S-1) et `1d` (J-1) préservent l'alignement ; `1h` (H-1) pour le grain fin. Variable dashboard `baseline` *single-select* `1h,1d,7d,28d` substituée via `shift:-$baseline:noquote` (cf. piège `:noquote` ci-dessous). Principe : un rythme stable d'une période équivalente à l'autre = **vert** (pas de bruit) ; seul l'écart vs la période équivalente précédente est un signal. (SLO/SLI par service = étape ultérieure, non disponible ici.)

## Piège — substitution de variable DQL : `:noquote` obligatoire pour duration/number

**Contexte** : dashboard Platform, variable de type ENUM/text (`$baseline = "7d"`), utilisée dans un paramètre DQL attendant une durée ou un nombre.

**Observation** : l'erreur du dashboard est `"the parameter has to be a number or a duration, but was a string"`. La requête verify_dql et itest passent pourtant.

**Cause** : Dynatrace substitue les variables texte/enum **avec guillemets** dans le DQL — `$baseline` devient `"7d"` (string). Or `shift:-"7d"` est invalide ; le paramètre `shift:` attend la durée brute `shift:-7d`.

**Faux-positif itest** : dans `sub()` on remplace manuellement `$baseline` par `7d` (raw) → le DQL envoyé à verify_dql / execute_dql est correct. Mais c'est différent de ce que le dashboard fait réellement. L'itest ne détecte pas ce piège.

**Résolution** : utiliser `$variable:noquote` dans le DQL — Dynatrace substitue alors la valeur brute, sans guillemets :

```dql
-- Avant (KO en dashboard live, OK en itest) :
timeseries ..., by:{k8s.namespace.name}, shift:-$baseline

-- Après (OK partout) :
timeseries ..., by:{k8s.namespace.name}, shift:-$baseline:noquote
```

Mettre à jour `sub()` dans itest pour traiter `$variable:noquote` **avant** `$variable` (éviter le match partiel) :

```javascript
const sub = q =>
  q.replace(/\$baseline:noquote/g, "7d")   // :noquote AVANT la version sans
   .replace(/\$baseline/g, "7d")
   ...
```

**Règle générale** : pour tout paramètre DQL attendant un **duration literal** ou un **number** (ex: `shift:`, `limit`, `from:`/`to:` avec durée) → toujours `$variable:noquote`. Ne pas faire confiance au itest seul pour valider ces cas.

## Ressources

- [📖1] [Best practices for scaling tagging and management-zone rules](https://docs.dynatrace.com/docs/manage/tags-and-metadata/basic-concepts/best-practice-tagging-at-scale)
- [📖2] [Maximum quantity of tiles in a dashboard? — Community](https://community.dynatrace.com/t5/Dashboarding/What-s-the-Maximum-quantity-of-tiles-in-a-dashboard-Dynatrace/td-p/110129)
- [📖3] [Rebuilding the Problems tile from Dashboards classic — Community](https://community.dynatrace.com/t5/DQL/Rebuilding-the-Problems-tile-from-Dashboards-classic-to-the-new/m-p/287547)
- [📖4] [Cut through the noise with segments (blog)](https://www.dynatrace.com/news/blog/cut-through-the-noise-with-segments-simple-powerful-and-dynamic-data-filtering/)
- [📖5] [From Management Zones to Segments (docs)](https://docs.dynatrace.com/docs/manage/segments/upgrade-guide-segments)
- [📖6] [Special configuration types Monaco — Dynatrace Docs](https://docs.dynatrace.com/docs/manage/configuration-as-code/monaco/configuration/special-configuration-types)
- [📖7] [DQL best practices — Dynatrace Docs](https://docs.dynatrace.com/docs/platform/grail/dynatrace-query-language/dql-best-practices)
- [📖8] [Reduce the number of Service Metrics created — Community](https://community.dynatrace.com/t5/Open-Q-A/Reduce-the-number-of-Service-Metrics-created/m-p/178838)
- [📖9] [TD Bank customer story — Dynatrace](https://www.dynatrace.com/customers/td-bank/)
- [📖10] [Dynatrace Perform 2026 — Diginomica](https://diginomica.com/dynatrace-perform-2026-why-do-observability-pocs-succeed-enterprise-rollouts-stall)
- [📖11] [Dynatrace Perform 2026: Observability The New Agent OS? — Futurum](https://futurumgroup.com/insights/dynatrace-perform-2026-is-observability-the-new-agent-os/)
- [📖12] [SLO burn rate monitoring — Dynatrace blog](https://www.dynatrace.com/news/blog/slo-monitoring-alerting-on-slos-error-budget-burn-rates/)
- [📖13] [Site Reliability Guardian — Dynatrace Docs](https://docs.dynatrace.com/docs/deliver/site-reliability-guardian)
