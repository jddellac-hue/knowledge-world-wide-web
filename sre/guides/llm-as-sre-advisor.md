---
name: llm-as-sre-advisor
description: Pattern de conception pour intégrer un LLM dans un outil SRE (observabilité, incident response, runbook assistant, postmortem synthesis) en mode advisory only — pas d'autopilote. 5 règles, anti-patterns, durcissement MCP tiers.
---

# LLM as SRE advisor — pattern advisory vs autopilot

Un LLM intégré dans un outil SRE (assistant on-call, générateur de tests, agent de diagnostic, synthèse postmortem) bascule vite vers un anti-pattern « **autopilote** » où l'IA exécute des actions opérationnelles (rollback, silence d'alerte, `kubectl apply/delete`, restart pod). Le pattern **advisory only** encadre cette intégration pour en tirer la valeur sans payer le prix d'une action automatique mal informée.

Ce guide formalise le pattern advisory en **5 règles** de conception applicables à tout outil SRE qui intègre un modèle génératif. Il s'appuie sur trois ancrages externes : la doctrine SRE *blameless postmortem* (Google SRE book, ch. 15) [📖¹](https://sre.google/sre-book/postmortem-culture/ "Google SRE Book — Postmortem Culture, ch. 15 (Beyer, Jones, Petoff, Murphy)"), l'OWASP Top 10 for LLM Applications (notamment LLM07 *Insecure Plugin Design*) [📖³](https://owasp.org/www-project-top-10-for-large-language-model-applications/ "OWASP Top 10 for Large Language Model Applications — LLM07 Insecure Plugin Design"), et le NIST AI Risk Management Framework, fonction *GOVERN* — *accountability* et *human oversight* [📖⁴](https://www.nist.gov/itl/ai-risk-management-framework "NIST AI Risk Management Framework (AI RMF 1.0) — GOVERN function").

## Pourquoi l'autopilote est tentant — et dangereux

Un LLM bien prompté sait formuler une commande de remédiation. Le passage à l'automatisation ressemble alors à une optimisation « logique » : si l'IA sait quoi faire, pourquoi ne pas le faire ? Trois raisons de résister :

1. **Les hallucinations ne disparaissent pas sous pression opérationnelle.** Les modèles statistiques peuvent inventer un commit, un paramètre de config, un nom de service. À 3h du matin, avec un incident en cours, aucun mécanisme n'empêche le LLM de produire une commande syntaxiquement valide mais sémantiquement fausse. ⚠️
2. **Le contexte d'un incident réel dépasse toujours le prompt.** Le LLM ne voit que ce qu'on lui donne : logs extraits, top métriques, runbook indexé. Il ne voit pas la réunion client en cours, la communication management qui impose un rollback même si le fix avance, la contrainte budgétaire qui empêche un scale-up. ⚠️
3. **La responsabilité doit rester humaine.** Un SRE qui rollback à tort mais en conscience apprend. Un LLM qui rollback à tort n'apprend rien et brouille la chaîne de responsabilité. Le pattern *blameless postmortem* suppose qu'un humain décide ; l'autopilote casse cet ancrage [📖¹](https://sre.google/sre-book/postmortem-culture/ "Google SRE Book — Postmortem Culture, ch. 15").

> ⚠️ **Pattern documenté en synthèse** — les 3 raisons sont consensuelles dans la communauté SRE et dans les guidelines responsables d'IA, mais cette triade en 3 points est une formulation didactique, pas un verbatim direct.

## Le pattern — 5 règles de conception

> **⚠️ Synthèse expérientielle** — Les 5 règles qui suivent ne sont pas tirées d'une source unique verbatim. Ce sont une **consolidation** de la doctrine SRE *blameless / human oversight* (Google SRE book/workbook ch. 7 *Evolution of Automation*), des principes OWASP Top 10 for LLM Applications (LLM02 *Insecure Output Handling*, LLM07 *Insecure Plugin Design*), du NIST AI Risk Management Framework (fonction *GOVERN* — accountability et human oversight), et de retours d'expérience industrielle sur l'intégration LLM en outil opérationnel. Confiance : 🟡 6/10. À adapter au contexte de gouvernance IA en place.

### Règle 1 — Le LLM ne touche jamais directement aux systèmes de production

Un outil SRE advisory a **zéro capacité d'écriture**. Il lit (logs, métriques, KB, postmortems, statuts API SLO/Prometheus), il résume, il suggère. Il **n'écrit pas**.

- ✅ Le LLM génère une commande `kubectl rollout undo deployment/<app>` et la **propose** à l'humain dans une UI ou un chat
- ❌ Le LLM exécute cette commande lui-même (directement ou via un outil MCP type `run_shell`)

L'implémentation concrète : les outils fournis au LLM (via MCP, function calling ou plugin) sont **tous en lecture seule**. Pas de `delete`, pas de `apply`, pas de `silence`, pas de `restart`. Si l'outil n'a pas les droits, le risque est mécaniquement nul — indépendamment de ce que le prompt demande.

### Règle 2 — Les hallucinations sont contrées par la factualité ancrée

La KB (runbooks, postmortems, CUJ, manifests SLO) est **la source de vérité**. Le LLM n'invente pas — il cite.

- ✅ Chaque affirmation technique dérive d'un fichier KB cité explicitement (format `<service>/runbooks/<name>.md`)
- ✅ Si la KB n'a pas la réponse, le LLM dit explicitement « aucun runbook indexé pour cette alerte, créer `<chemin>/<nom>.md` avec le template »
- ❌ Le LLM improvise une procédure non documentée

L'implémentation concrète : le prompt système impose **citations obligatoires**. L'absence de citation est un **signal d'hallucination** que le LLM doit lui-même détecter et corriger. Des outils MCP factuels (recherche KB, lecture fichier, interrogation API SLO) fournissent l'ancrage. Cf. pattern Model Context Protocol [📖²](https://modelcontextprotocol.io/ "Anthropic — Model Context Protocol (introduction, 2024)").

### Règle 3 — La revue humaine est un gate, pas une formalité

Tout draft produit par un LLM (postmortem pré-rédigé, test généré, plan de remédiation) passe par une revue humaine **avant** d'entrer dans le système opérationnel.

- ✅ Header d'avertissement `⚠️ Draft IA — relire et compléter avant commit` dans les fichiers générés
- ✅ Hook `pre-commit` qui refuse le commit si le header est encore présent
- ✅ PR obligatoire pour tout test / runbook / postmortem généré par IA
- ❌ Auto-merge sur les PRs marquées « generated by IA »

L'implémentation concrète : le workflow CI force la revue. Un humain lit, adapte, valide. Le SRE reste auteur — l'IA est assistant.

### Règle 4 — La supervision conso et la traçabilité sont de première classe

Chaque appel LLM est supervisé : quel cas d'usage, quel modèle, combien de tokens, quel `correlation_id` (trace ID propagé). Pas d'appel LLM « sauvage ».

- ✅ Un identifiant de cas d'usage (typiquement nom d'application + tag d'usage) **fixé avant mise en service**, jamais mutualisé entre cas d'usage
- ✅ Dashboard conso : requêtes/jour, erreurs, latence p99, tokens consommés
- ✅ Trace distribuée : `correlation_id` propagé du client (chat, CLI, pipeline) jusqu'au LLM
- ❌ Token LLM partagé entre plusieurs outils
- ❌ Conso invisible — pas de dashboard

L'implémentation concrète : un wrapper interne (ou une gateway LLM mutualisée) impose ces headers de supervision et expose un dashboard conso par cas d'usage. Si la gateway ne le fait pas nativement, l'instrumentation se fait côté wrapper.

### Règle 5 — Advisory only explicite dans le prompt système

Le prompt système de chaque outil SRE advisory inclut **littéralement** l'interdiction d'action :

```
Tu es un assistant <rôle>. Règles absolues :

1. ADVISORY ONLY. Tu ne proposes JAMAIS d'exécuter une action destructive
   (rollback automatique, kubectl delete, silence d'alerte, restart pod,
   scale-up/scale-down). Tu peux citer la commande qu'un humain pourrait
   lancer — jamais l'exécuter.

2. FACTUALITÉ. Si la KB ne contient pas la réponse, dis-le explicitement.
   JAMAIS d'invention.

3. CITATIONS OBLIGATOIRES. Chaque affirmation technique cite le fichier source.

4. ESCALADE. Si la question sort du périmètre, dire « hors périmètre »
   et renvoyer vers l'équipe / doc appropriée.
```

Ce préambule est **versionné**, lu en revue de code, audité comme n'importe quel code critique. Un changement du prompt système = un changement de version = une revue.

## Anti-patterns à proscrire

### 🚫 L'agent d'incident response auto-remédiant

Un LLM branché sur Alertmanager qui, à la réception d'une alerte burn-rate, exécute automatiquement le runbook associé (rollback, scale-up, silence). Tentant — dangereux. L'IA n'a pas le contexte métier (est-ce qu'on est vendredi soir avant une release majeure ? est-ce qu'un incident client en cours interdit le rollback ?). ❌

**Alternative advisory** : l'IA **propose** la remédiation dans le canal d'incident (Slack, Teams) avec les commandes à copier-coller. L'humain décide.

### 🚫 Le LLM qui écrit dans la KB sans revue

Un LLM qui auto-commit ses enrichissements de KB, ses nouveaux runbooks, ses mises à jour de postmortems. Le risque de dérive sémantique (KB qui commence à contenir des infos hallucinées) est réel — et **invisible** à moyen terme. ❌

**Alternative advisory** : l'IA rédige des **PRs** avec le diff proposé, un humain relit et merge. Tout commit IA passe par un humain.

### 🚫 Le fallback silencieux vers un LLM externe

En cas d'indisponibilité du LLM auto-hébergé (gateway mutualisée, modèle on-prem, etc.), basculer automatiquement vers un service externe public — *« juste pour ne pas casser le workflow »*. Viole la gouvernance des données : les données qui ne devaient jamais sortir du SI partent vers un tiers. ❌

**Alternative advisory** : le fallback = **service indisponible**. L'outil SRE affiche une erreur claire, l'humain travaille manuellement le temps du retour du LLM auto-hébergé. Pas de contournement, même sous dérogation ponctuelle.

### 🚫 Le prompt système qui laisse la porte ouverte

Un prompt système du type *« tu peux proposer des actions de remédiation »* sans exclusion explicite des actions destructives. Le LLM, en voulant être serviable, glisse vers l'autopilote. ❌

**Alternative advisory** : liste blanche des actions proposables (lire, résumer, citer) ; **liste noire** explicite des actions interdites (exécuter, silencier, rollback, `kubectl delete`…).

### 🚫 L'absence de traçabilité bout-en-bout

Un client IA qui appelle un LLM qui appelle un outil MCP qui appelle une API — sans trace distribuée commune. Un incident causé par une réponse LLM devient impossible à rejouer. ❌

**Alternative advisory** : `correlation_id` / `trace_id` propagé de bout en bout. Post-incident, on rejoue la chaîne pour comprendre ce que le LLM a vu et produit.

## Modes d'usage — compatibles vs incompatibles

Cas d'usage qui respectent le pattern advisory :

| Cas d'usage | Description | Risque si advisory respecté |
|---|---|---|
| **Runbook assistant on-call** | Recherche du runbook pertinent, synthèse contextualisée, proposition de commandes à copier-coller | Faible — humain décide |
| **Postmortem synthesis** | Draft pré-rédigé depuis matériaux bruts (logs, chat d'incident, transcription audio), revue humaine obligatoire | Faible — gate PR |
| **Génération de tests smoke** | Tests JUnit / k6 / Playwright générés depuis OpenAPI ou traces, PR pour revue | Faible — gate PR |
| **Analyse de code / changelog** | Résumé d'un diff, génération d'un message de commit | Faible — humain commit |
| **Root cause hypotheses** | Agent qui lit métriques + logs + déploiements récents et **liste les hypothèses ordonnées** (pas de verdict) | Faible — humain tranche |
| **Onboarding SRE** | Assistant qui explique la stack, les conventions, les outils à partir de la KB | Très faible — pas de prod touchée |

Cas d'usage qui **violent** le pattern advisory (à proscrire ou encadrer très strictement) :

| Cas d'usage | Risque |
|---|---|
| Auto-remédiation sur alerte | Autopilote — voir anti-pattern ci-dessus |
| Auto-silence d'alertes bruyantes | Perte de signal, faux négatifs masqués |
| Auto-scale / auto-rollback | Décision critique sans contexte métier |
| Auto-tuning de SLO / thresholds | Drift invisible des SLO vers l'accommodement |
| Génération de code + auto-merge | Dérive qualité / sécurité, pas de revue humaine |

## Intégration MCP tiers : patterns de durcissement

> **⚠️ Synthèse expérientielle** — Les patterns de durcissement (fork interne, allow-list, wrapper PII, supervision conso) sont une **consolidation** des principes OWASP LLM07 *Insecure Plugin Design*, des bonnes pratiques supply-chain (SLSA, NIST SSDF), et de retours d'expérience d'intégration MCP en environnement régulé. Pas un standard publié verbatim. Confiance : 🟡 6/10.

Le Model Context Protocol (MCP) [📖²](https://modelcontextprotocol.io/ "Anthropic — Model Context Protocol (introduction, 2024)") a fait exploser le nombre de MCP Servers tiers disponibles (observabilité, APM, ticketing, monitoring). L'écosystème inclut des projets officiels-éditeurs, des projets open source communautaires, et des serveurs forkés. Leur intégration dans un outil SRE advisory soulève **trois questions** spécifiques qui ne se posent pas pour une KB interne.

### Question 1 — Qui maintient le MCP et quel est son statut de support ?

Trois statuts possibles, chacun avec ses implications :

| Statut | Exemple type | Implications |
|---|---|---|
| **Officiellement supporté par l'éditeur** | MCP publié et supporté comme produit (rare à date) | SLA, patches de sécurité, compatibilité API garantie |
| **Communautaire éditeur** (org open-source de l'éditeur, non-produit) | Repo GitHub `<vendor>-oss/<vendor>-mcp` explicitement marqué *"Not officially supported"* | Code open source, roadmap éditeur possible, **pas de SLA**, risque d'abandon |
| **Communautaire tiers** | Forks, MCP écrits par des indépendants | Revue de sécurité obligatoire, supply chain à maîtriser |

**Règle** : aucun MCP tiers n'est branché directement à un client LLM de production. Toujours un **fork interne** dans un registry/Artifactory interne + scan de sécurité initial + rebase contrôlé. Le MCP tiers est une **dépendance** au sens `package.json`, pas un service externe.

### Question 2 — Quelles capacités expose-t-il vraiment ?

La plupart des MCP tiers exposent un mélange de lecture et d'écriture. Exemple : un MCP d'APM peut exposer `query_traces` (lecture, sans risque) **et** `create_workflow`, `send_notification`, `silence_alert` (écriture, violation de la règle 1 advisory).

**Anti-pattern** : brancher le MCP tel quel en comptant sur le prompt système pour empêcher le LLM d'appeler les outils d'écriture. Un prompt n'est pas une frontière de sécurité. Le LLM peut halluciner un appel, un utilisateur peut prompt-injecter, un changement upstream peut ajouter un nouvel outil non anticipé.

**Pattern correct** : interposer un **wrapper** minimaliste qui :

1. Relaye uniquement les outils explicitement whitelistés (allow-list, pas deny-list)
2. Bloque les autres avec `ErrorCode.MethodNotFound` — le LLM ne les voit pas dans `tools/list`
3. Fait l'objet d'une revue à chaque rebase sur l'upstream (nouveau outil upstream ≠ exposé par défaut)

### Question 3 — Que voient les données de prod au passage du MCP ?

Un MCP qui interroge l'APM ramène des **traces de production réelles** : URLs avec IDs métier, bodies HTTP, logs avec messages d'erreur. Là où s'applique du RGPD ou un cadre de protection des données analogue, ces payloads peuvent contenir des données personnelles (identifiants nationaux, emails, téléphones, références utilisateur).

**Anti-pattern** : filtrage côté client LLM (dans le prompt system ou le script appelant). Un client oubliant le filtrage = une fuite. Une nouvelle équipe qui intègre une nouvelle slash-command = potentiellement un nouveau point d'oubli. La discipline ne remplace pas l'architecture.

**Pattern correct** : le **filtrage des données personnelles vit dans le wrapper**, en sortie de chaque outil exposé. **Point de contrôle unique**, maintenu par l'équipe SRE, audité, testé. Ajouter un nouveau client = zéro risque supplémentaire : le filtrage a déjà eu lieu.

Patterns regex de base à adapter à la juridiction et à valider avec le Data Protection Officer (ou équivalent local — *RSSI*, *Privacy Officer*, *Compliance Officer*) avant prod :

```
email                  : [\w.+-]+@[\w.-]+\.[a-z]{2,}
téléphone              : <regex format local — ex. France : 0[1-9](?:[\s.-]?\d{2}){4}>
IDs URL                : /users/\d+ → /users/<ID>
identifiants nationaux : <regex propre à la juridiction, à valider conformité>
```

Métriques à exposer pour détecter une régression du filtre :

- `pii_substitutions_total{pattern}` — compteur par pattern, agrégé
- Alerte sur **pic** anormal (souvent = donnée non filtrée qui passe maintenant, filtre régressé)
- **Pas** de log des valeurs originales (sinon le log devient lui-même source de fuite)

### Cheatsheet — avant d'intégrer un MCP tiers dans un outil SRE

- [ ] Identifier le **statut de support** (officiel / communautaire éditeur / communautaire tiers)
- [ ] **Fork interne** dans le registry/Artifactory, pin de version strict
- [ ] **Scan initial** (audit dépendances, scan secrets, revue des outils exposés)
- [ ] **Allow-list** explicite des outils en lecture — pas de deny-list
- [ ] **Wrapper** qui masque tout outil d'écriture
- [ ] **Filtrage PII** en sortie de chaque outil en lecture, côté wrapper (point unique)
- [ ] **Budget d'appels** configuré (quota par requête, par minute) + alerte à 80 %
- [ ] **Authentification** avec token de service dédié, scope lecture seule, dans un coffre-fort de secrets
- [ ] **Déclaration** du cas d'usage auprès du comité gouvernance IA interne
- [ ] **Rebase périodique** sur l'upstream, avec revue manuelle de changelog
- [ ] **Tests d'intégration** quotidiens (détecter les régressions upstream)
- [ ] **Procédure de continuité** si l'upstream est abandonné (reprise maintenance en interne)

### Cas limite — MCP qui embarque un LLM tiers (double LLM)

Certains MCP exposent l'IA de leur éditeur en plus de la donnée brute (exemple : un outil `chat_with_vendor_ai`). On se retrouve alors avec **deux LLM dans la chaîne** : le LLM de la session principal + le LLM tiers exposé via l'outil. Implications :

- Les prompts envoyés à l'outil `chat_with_vendor_ai` **sortent** vers le vendor — à considérer comme un envoi à un service externe, soumis aux règles de gouvernance des données qui s'appliquent
- Gouvernance doublée : chaque LLM a ses propres conditions de service, sa propre supervision, son propre niveau de confidentialité
- Tracing : deux chaînes de requêtes à corréler pour déboguer un incident IA

**Recommandation** : soit **masquer** l'outil via le wrapper (option par défaut), soit passer l'appel par le filtre PII **avant** envoi au vendor, avec déclaration explicite du flux au comité de gouvernance. Ne jamais exposer tel quel.

## Métriques de santé d'un outil SRE advisory

Pour vérifier que le pattern tient dans la durée :

- **Taux de PR mergées sans modification** (tests générés, drafts postmortem) — > 80 % = trop automatique, dérive vers l'autopilote masqué ; < 50 % = prompts à itérer
- **Taux de réponses avec citation KB** (pour runbook / postmortem assistant) — cible > 95 %
- **Taux d'escalade explicite** (« hors périmètre, contacter X ») — présence = bon signe (le LLM ne bricole pas)
- **Nombre d'incidents causés par une réponse LLM suivie sans vérification** — cible 0 ; post-incident, analyser si le pattern advisory a été respecté
- **Conso LLM par cas d'usage** — dashboard par `application_name`, détection de dérives de coût

## Cheatsheet — avant de déployer un outil SRE intégrant un LLM

- [ ] Les outils exposés au LLM (MCP, function calling) sont **tous en lecture seule** — pas de `delete`, `apply`, `silence`, `restart`
- [ ] Le prompt système inclut l'interdiction **littérale** d'action destructive (règle 5)
- [ ] Les citations de la KB sont **obligatoires** et vérifiables
- [ ] Les drafts générés portent un header `⚠️ Draft IA — à relire`
- [ ] Hook pré-commit / CI refuse les drafts non relus
- [ ] Cas d'usage déclaré auprès du comité gouvernance IA interne
- [ ] Identifiant de cas d'usage fixé et non mutualisé — supervision conso active
- [ ] Fallback en cas de LLM indisponible = **service indisponible**, pas de bascule externe
- [ ] Trace distribuée : `correlation_id` propagé client → LLM → outils
- [ ] Filtrage PII en amont pour les cas d'usage qui ingèrent des données de production (logs, traces, chat)
- [ ] Documentation utilisateur insiste sur l'esprit critique — la réponse LLM **se vérifie**

## Ressources

1. [Postmortem Culture: Learning from Failure](https://sre.google/sre-book/postmortem-culture/) — Google SRE Book, ch. 15 : blameless + responsabilité humaine de la décision.
2. [Model Context Protocol — Introduction](https://modelcontextprotocol.io/) — Anthropic, 2024 : outils factuels comme ancrage anti-hallucinations.
3. [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/) — OWASP : prompt injection, sensitive information disclosure, supply chain (utile pour la durcissement MCP tiers).
4. [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework) — NIST AI RMF 1.0 : cadre de gestion des risques IA, applicable au pattern advisory.

## Conventions de sourcing

- `[📖n](url "tooltip")` — Citation **vérifiée verbatim** via WebFetch / lecture directe des sources
- ⚠️ — Reformulation pédagogique ou pattern consensuel non cité verbatim

Notes de confiance : 🟢 9-10 (verbatim) / 🟢 7-8 (reformulation fidèle) / 🟡 5-6 (choix défendable) / 🟠 3-4 (choix d'équipe) / 🔴 1-2 (à challenger).

## Liens internes KB

- [`monitoring-alerting.md`](monitoring-alerting.md) — Philosophie d'alerting (page on symptoms, pas causes)
- [`incident-management.md`](incident-management.md) — Conduite d'incident (où l'IA peut aider en mode advisory)
- [`oncall-practices.md`](oncall-practices.md) — Pratiques d'astreinte (où le runbook assistant intervient)
- [`postmortem.md`](postmortem.md) — Postmortem blameless (où l'IA assiste la rédaction)
- [`sre-at-scale.md`](sre-at-scale.md) — Modèles d'organisation SRE à l'échelle (où la plateforme IA-advisory s'inscrit comme capacité)
