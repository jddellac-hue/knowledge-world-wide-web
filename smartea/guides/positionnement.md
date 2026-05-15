# SmartEA — Positionnement, éditeur, clients

## Obeo, l'éditeur

> *"Founded in 2005, Obeo is a leading independent software vendor specializing in Model-Based Systems Engineering (MBSE), Enterprise Architecture (EA), and other domain-specific modeling needs."* [📖¹](https://www.obeosoft.com/en/company/ "Obeo — page Company, fondation 2005, MBSE + EA + DSL")
>
> *En français* : **Obeo est un éditeur indépendant français fondé en 2005**, spécialisé dans l'ingénierie système basée modèle (MBSE), l'Enterprise Architecture (EA) et les langages de modélisation métier.

**Bureaux** : Nantes (siège), Paris, Toulouse, Vancouver. **Effectif** : ~50 personnes (estimation, non publique). **Indépendance** : Obeo n'est pas filiale d'un grand éditeur, ce qui distingue le produit dans un marché en consolidation rapide (cf. [`comparaison-alternatives.md`](comparaison-alternatives.md)).

Obeo est aussi l'**éditeur principal** de plusieurs briques open source largement utilisées dans l'écosystème Eclipse :

| Brique | Rôle | Lien |
|---|---|---|
| **Eclipse Sirius** | Framework de création d'éditeurs graphiques sur EMF (créé par Obeo + Thales) | [Sirius](https://www.eclipse.org/sirius/ "Eclipse Sirius — framework éditeurs graphiques EMF") |
| **Eclipse Sirius Web** | Évolution web-native de Sirius (React + Spring Boot + GraphQL) | [Sirius Web](https://eclipse.dev/sirius/sirius-web.html "Eclipse Sirius Web — version web-native") |
| **Eclipse Capella** | MBSE — méthode + outil pour ingénierie système (Arcadia) | [Capella](https://www.eclipse.org/capella/ "Eclipse Capella — MBSE / Arcadia") |
| **Eclipse EMF Compare** | Comparaison et merge de modèles EMF | [EMF Compare](https://www.eclipse.org/emf/compare/ "Eclipse EMF Compare") |
| **Eclipse Acceleo / AQL** | Langage de requête et génération sur EMF | [Acceleo](https://www.eclipse.org/acceleo/ "Eclipse Acceleo — langage de requête EMF") |

Cette **maîtrise verticale** de la stack open source sous-jacente est un argument de pérennité : Obeo n'est pas dépendant d'un éditeur tiers pour faire évoluer le cœur de SmartEA.

## SmartEA, le produit

> *"graphical and collaborative Continuous Enterprise Architecture solution enabling you to map your organization and its IT system"* [📖²](https://www.obeosoft.com/en/products/smartea/ "Obeo SmartEA — page produit")
>
> *En français* : **solution d'EA continue, graphique et collaborative**, conçue pour cartographier l'organisation et son SI.

| Dimension | Valeur |
|---|---|
| Année de listing Eclipse Marketplace | **8 juin 2012** [📖³](https://marketplace.eclipse.org/content/obeo-smartea "Eclipse Marketplace — Obeo SmartEA") |
| License | **Commercial** [📖³](https://marketplace.eclipse.org/content/obeo-smartea "Eclipse Marketplace — license commerciale") |
| Version courante | **9.1.1** (sortie 31 mars 2026) [📖⁴](https://www.obeosoft.com/en/products/smartea/changelog "Obeo SmartEA — Changelog") |
| Cycle de release | ~4 versions majeures par an (v8.4 mai 2025 → v8.5 oct. 2025 → v9.0 fév. 2026 → v9.1 mars 2026) [📖⁴](https://www.obeosoft.com/en/products/smartea/changelog "Obeo SmartEA — Changelog") |
| Tarification | Modèle commercial B2B sur devis, **per-user pricing**, pas de tarif public [📖⁵](https://www.capterra.com/p/231378/Obeo-SmartEA/ "Capterra — Obeo SmartEA, pricing model") |
| Essai | Gratuit, sans carte de crédit [📖⁵](https://www.capterra.com/p/231378/Obeo-SmartEA/ "Capterra — Obeo SmartEA, essai gratuit") |

## Clients documentés

| Client | Secteur | Cas d'usage documenté |
|---|---|---|
| **Chorégie** | Groupe mutualiste santé (France) | *« uses the Obeo SmartEA solution to master its enterprise architecture and to manage strategic transformation plans »* — automatisation des diagrammes depuis tracking data [📖⁶](https://www.obeosoft.com/en/company/customers/ "Obeo — Customers, Chorégie use case") |
| **MAIF** | Assurance (France) | *« needed a tool providing a structured, centralized and unified vision of P&C (property and casualty) products »* — workbench Sirius custom pour catalogue produits [📖⁶](https://www.obeosoft.com/en/company/customers/ "Obeo — Customers, MAIF use case") |

**Clients Obeo groupe** (pas tous SmartEA — beaucoup utilisent Capella pour MBSE) : Thales, Airbus, Safran, CEA, ESA, Rolls-Royce, ArianeGroup, Deutsche Bahn, Siemens, UKAEA. Obeo revendique ~**200 clients** au total [📖¹](https://www.obeosoft.com/en/company/ "Obeo — Company, ~200 clients groupe").

> ⚠️ **Visibilité publique faible** : 0 reviews Capterra/G2 pour SmartEA → impossible de chiffrer la satisfaction utilisateur via avis indépendants. La plupart des références publiques sont des case studies pilotés par Obeo.

## Cas d'usage typiques

D'après les case studies publics et le positionnement Obeo, SmartEA est utilisé pour :

1. **Cartographie SI** d'organisations grandes (centaines à milliers d'applications)
2. **Gouvernance / urbanisme** — qui possède quoi, dépendances, conformité
3. **Programmes de transformation digitale** — modélisation AS-IS / TO-BE et trajectoires
4. **Catalogue produits métier** (MAIF) — référentiel structuré multi-vues
5. **Audit et conformité** — traçabilité des composants applicatifs et flux

> ⚠️ **Lien SRE / chaînes de valeur runtime** : non documenté publiquement par Obeo. Le rapprochement EA × SRE (cf. [`sre-link.md`](sre-link.md)) est un **pattern à construire**, pas un usage out-of-the-box.

## Forces et limites synthétiques

### 🟢 Forces

1. **Stack open source maîtrisée** : Obeo édite Sirius/EMF/Sirius Web → indépendance technique forte
2. **Standards officiels à jour** : ArchiMate 3.2, BPMN 2.0 avec export OMG XML, traçabilité ArchiMate ↔ BPMN
3. **Branches type Git pour trajectoires** : différenciateur fort vs LeanIX et Bizzdesign
4. **Métamodèle / vues / connecteurs sur-mesurables** via Sirius
5. **Cycle de release soutenu** + investissement IA récent (recherche LLM → AQL en beta)
6. **Indépendance** dans un marché en consolidation autour de SAP-LeanIX / Bizzdesign

### 🟡 Limites

1. **Visibilité publique faible** : 0 reviews Capterra/G2 → benchmarking utilisateur difficile
2. **Pas de SaaS multi-tenant pure** : déploiement on-prem ou cloud dédié (vs LeanIX SaaS)
3. **Tarification opaque** : pas de prix publics, achat sur devis uniquement
4. **UML/SysML absents** : pour unifier EA + ingénierie système, il faut combiner SmartEA + Capella
5. **Catalogue connecteurs natifs limité publiquement** : APIs ouvertes oui, mais peu de connecteurs out-of-the-box visibles (pas de marketplace Confluence/JIRA/ServiceNow documentée)
6. **Communauté restreinte** vs Sparx EA (forum très actif) ou Archi (utilisateurs OSS nombreux)

> **🟢 Confiance 7/10** sur les forces (vérifiables via doc Obeo et stack open source) ; **🟡 Confiance 5/10** sur les limites (l'absence de reviews indépendantes empêche de quantifier la satisfaction réelle).

## Liens

- [`architecture.md`](architecture.md) — Stack technique détaillée
- [`standards-modelisation.md`](standards-modelisation.md) — ArchiMate / BPMN / TOGAF
- [`comparaison-alternatives.md`](comparaison-alternatives.md) — vs LeanIX / Sparx / Bizzdesign / Mega / Archi
- [`sre-link.md`](sre-link.md) — Lien avec une démarche SRE / Continuous Architecture
