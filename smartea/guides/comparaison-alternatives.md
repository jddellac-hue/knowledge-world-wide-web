# SmartEA — Comparaison avec les alternatives EA

## Tendance marché 2025-2026

> *"SAP's acquisition of LeanIX and the full unification of MEGA HOPEX, Alfabet, and Horizzon under the Bizzdesign brand"* [📖¹](https://digitalmehmet.com/2026/03/04/enterprise-architecture-tooling-in-2026/ "Digitalmehmet — EA Tooling 2026, consolidation marché")
>
> *En français* : **consolidation forte** du marché EA en 2025-2026 autour de deux pôles : **SAP-LeanIX** (SaaS) et **Bizzdesign** (qui unifie HOPEX, Alfabet et HoriZZon). SmartEA reste un **acteur indépendant français**.

## Tableau comparatif synthétique

| Outil | Modèle | Cible marché | Standards forts | Différenciateur clé | Visibilité |
|---|---|---|---|---|---|
| **Obeo SmartEA** | Commercial, on-prem ou cloud dédié | Niche francophone, EA pure | ArchiMate 3.2, BPMN 2.0 | Branches type Git, stack OSS Sirius maîtrisée | 🔴 0 reviews G2/Capterra |
| **[LeanIX](https://www.leanix.net/ "LeanIX — SaaS EA, racheté par SAP")** | SaaS multi-tenant (SAP) | Grand marché, portfolio-centric | Référentiel propriétaire | SaaS moderne, intégrations natives nombreuses | 🟢 4.7★ 446 reviews G2 |
| **[Sparx EA](https://sparxsystems.com/ "Sparx Systems — Enterprise Architect")** | Commercial desktop + cloud | Communauté technique large | UML, SysML, ArchiMate, BPMN | UML/SysML solide, prix abordable | 🟡 3.7★ 203 reviews |
| **[Bizzdesign HoriZZon](https://bizzdesign.com/ "Bizzdesign — HoriZZon, leader ArchiMate")** | Commercial entreprise | Leader ArchiMate mainstream | ArchiMate, TOGAF | Leader marché, vient d'absorber HOPEX et Alfabet | 🟢 Reconnu Gartner |
| **[MEGA HOPEX](https://www.mega.com/ "MEGA — HOPEX, EA + GRC")** | Commercial (acquis par Bizzdesign) | EA + GRC + risk | ArchiMate, framework GRC | GRC + risk + conformité intégrés | 🟢 Reconnu Gartner |
| **[Avolution Abacus](https://www.avolutionsoftware.com/ "Avolution — Abacus, multi-framework")** | Commercial | Multi-framework | TOGAF, ArchiMate, DoDAF, NAF | Forte analytique, multi-framework | 🟡 Niche |
| **[Archi](https://www.archimatetool.com/about/ "Archi — outil ArchiMate desktop OSS")** | Open Source (gratuit) | Praticiens individuels | ArchiMate 3.1 | Le plus utilisé en OSS, communauté forte | 🟢 Communauté large |
| **[Modelio](https://www.modelio.org/ "Modelio — UML/BPMN/ArchiMate OSS")** | Open Source | Communauté technique | UML, BPMN, ArchiMate | Open source multi-langages | 🟡 Communauté moyenne |

## Comparaison détaillée — différenciateurs clés

### vs LeanIX (SaaS SAP)

**Forces de SmartEA** :
- ✅ Pas de SaaS multi-tenant → contrôle total des données (souveraineté)
- ✅ Branches type Git pour trajectoires (LeanIX n'a pas ce modèle documenté)
- ✅ Modélisation ArchiMate plus pure (LeanIX est plus *portfolio* qu'*ArchiMate*)
- ✅ Métamodèle modifiable

**Forces de LeanIX** :
- ✅ Catalogue de connecteurs natifs immense (ServiceNow, Microsoft, Atlassian, etc.)
- ✅ SaaS prêt à l'emploi en jours
- ✅ 446 reviews G2 4.7★ — base utilisateurs et retours nombreux
- ✅ Backing SAP — pérennité business forte

**Verdict** : SmartEA est le choix si on veut maîtriser le déploiement et avoir des branches type Git. LeanIX si on veut un SaaS moderne avec connecteurs prêts.

### vs Sparx EA (UML/SysML)

**Forces de SmartEA** :
- ✅ Vraie collaboration web (Sparx EA est principalement desktop, modèle co-édition limité)
- ✅ Branches type Git
- ✅ Stack moderne (React, Spring, GraphQL) vs Sparx desktop natif

**Forces de Sparx EA** :
- ✅ **UML + SysML** intégral (SmartEA n'a pas UML/SysML)
- ✅ Communauté énorme (3.7★ 203 reviews G2 + forums actifs)
- ✅ Prix très abordable
- ✅ Multi-framework

**Verdict** : SmartEA pour EA pure (ArchiMate + BPMN) avec collaboration ; Sparx EA si l'organisation a besoin d'UML/SysML pour l'ingénierie système — ou combiner SmartEA + Capella (cf. [`positionnement.md`](positionnement.md)).

### vs Bizzdesign HoriZZon (leader ArchiMate)

**Forces de SmartEA** :
- ✅ Indépendance francophone (vs consolidation Bizzdesign-HOPEX-Alfabet)
- ✅ Cycle de release rapide (4 versions/an)
- ✅ Stack OSS Sirius maîtrisée par l'éditeur

**Forces de Bizzdesign** :
- ✅ Reconnu Gartner Magic Quadrant
- ✅ Largement déployé en grandes entreprises
- ✅ Catalogue d'analytics et dashboards plus mature
- ✅ Méthodologie ArchiMate de référence (CTO Bizzdesign = Marc Lankhorst, l'un des auteurs ArchiMate)

**Verdict** : SmartEA si on cherche un acteur indépendant et léger ; Bizzdesign si on veut le leader marché avec écosystème étendu.

### vs MEGA HOPEX (EA + GRC français)

**Forces de SmartEA** :
- ✅ EA pure et modulaire (pas de surplus GRC si non utilisé)
- ✅ Stack moderne (Sirius Web)
- ✅ Plus léger et abordable

**Forces de MEGA** :
- ✅ **GRC + risk + conformité intégrés** (différenciateur fort en finance, banque, secteur régulé)
- ✅ Acteur français de longue date
- ✅ Reconnu Gartner

**Verdict** : SmartEA si EA pure ; MEGA si organisation a besoin d'EA + GRC dans un seul outil.

### vs Avolution Abacus

**Forces de SmartEA** :
- ✅ Stack OSS Sirius (transparence, pérennité)
- ✅ Plus simple à prendre en main
- ✅ Cycle de release plus rapide

**Forces d'Abacus** :
- ✅ **Multi-framework** : TOGAF, ArchiMate, DoDAF, NAF, FEAF dans un seul outil
- ✅ Forte analytique (calculs sur le modèle)
- ✅ Adopté secteur défense / gouvernement (NAF, DoDAF)

**Verdict** : SmartEA si ArchiMate + BPMN suffisent ; Abacus si frameworks militaires/gouvernementaux nécessaires.

### vs Archi (OSS desktop)

**Forces de SmartEA** :
- ✅ Repository centralisé multi-utilisateur (Archi est mono-utilisateur)
- ✅ Web + collaboration + branches
- ✅ ArchiMate **3.2** (Archi est **3.1**)
- ✅ Génération Word M2Doc, recherche LLM, gap analysis avancée

**Forces d'Archi** :
- ✅ **Gratuit** (OSS sous licence MIT)
- ✅ Plus de **15 ans** d'historique, communauté massive
- ✅ Plugins communautaires nombreux (jArchi pour scripting, coArchi pour partage Git)

**Verdict** : Archi pour un usage individuel ou équipe small + budget limité ; SmartEA pour entreprise avec collaboration multi-architectes et trajectoires.

### vs Modelio (OSS multi-langages)

**Forces de SmartEA** :
- ✅ Web-natif (Sirius Web)
- ✅ Branches Git, gap analysis avancée
- ✅ Cycle de release rapide

**Forces de Modelio** :
- ✅ **Gratuit** (OSS)
- ✅ Multi-langages : UML, BPMN, ArchiMate
- ✅ TOGAF / Archimate Open Exchange Format

**Verdict** : Modelio pour un usage OSS multi-langages ; SmartEA pour entreprise commerciale avec collaboration moderne.

## Résumé : quand choisir SmartEA ?

✅ **Choix SmartEA pertinent quand** :
- Préférence pour un éditeur **indépendant français** dans un marché en consolidation
- Besoin de **modéliser des trajectoires** de transformation (branches type Git)
- Volonté de garder le **contrôle** des données (on-prem ou cloud dédié)
- Stack **ArchiMate + BPMN** suffit (pas besoin d'UML/SysML, pas de GRC, pas de DoDAF)
- Tolérance à un catalogue de **connecteurs natifs limité** (compensé par APIs ouvertes)
- Acceptation d'une **visibilité publique faible** (peu de reviews, à benchmarker en interne)

❌ **Préférer une alternative si** :
- Besoin **SaaS multi-tenant** prêt en jours → LeanIX
- Besoin **UML/SysML** pour l'ingénierie système → Sparx EA (ou SmartEA + Capella)
- Besoin **GRC + risk + conformité** intégrés → MEGA HOPEX
- Besoin **multi-framework** (DoDAF, NAF, FEAF) → Avolution Abacus
- Besoin d'une **communauté massive** ArchiMate → Bizzdesign HoriZZon ou Archi (OSS)
- **Budget gratuit** → Archi ou Modelio (OSS)

## Liens

- [`positionnement.md`](positionnement.md) — Identité Obeo et marché
- [`standards-modelisation.md`](standards-modelisation.md) — Standards supportés / non supportés
- [Digitalmehmet — EA Tooling 2026](https://digitalmehmet.com/2026/03/04/enterprise-architecture-tooling-in-2026/ "Digitalmehmet — Enterprise Architecture Tooling in 2026")
