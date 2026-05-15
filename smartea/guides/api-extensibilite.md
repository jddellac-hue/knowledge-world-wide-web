# SmartEA — API & extensibilité

## APIs ouvertes

> *"Obeo SmartEA open APIs allow for connectors that can supply the repository according to your needs and according to every data source type"* [📖¹](https://www.obeosoft.com/en/products/smartea/features "Obeo SmartEA — Features, APIs ouvertes pour connecteurs")
>
> *En français* : **APIs ouvertes** pour brancher n'importe quelle source de données. Chaque organisation construit ses connecteurs sur-mesure selon ses sources existantes.

> ⚠️ Les sources publiques fetchées **ne détaillent pas** la nature exacte des APIs (REST ? GraphQL ? SDK Java ?) — vu le socle technique Sirius Web (cf. [`architecture.md`](architecture.md)) qui utilise GraphQL, il est très probable que SmartEA expose une API GraphQL côté web. Point à confirmer en avant-vente.

## Web services Excel typés (v9.1.0)

> *"Introduced stereotyped XLSX export/import web services"* (v9.1.0) [📖²](https://www.obeosoft.com/en/products/smartea/changelog "Obeo SmartEA — Changelog, web services XLSX stéréotypés v9.1.0")
>
> *En français* : **web services Excel stéréotypés** introduits en v9.1.0 — automatisation des flux d'import/export Excel.

Pattern d'usage : un script externe (Python, Node, shell) appelle l'endpoint web service, fournit un Excel typé en entrée, récupère un Excel ou un statut en sortie. Permet d'**industrialiser** les flux de mise à jour depuis CMDB / catalogue applicatif / extracts BDD.

## AQL — scripting et services custom

[AQL (Acceleo Query Language)](https://www.eclipse.org/acceleo/ "Eclipse Acceleo — AQL, langage de requête EMF") est le langage de requête historique de l'écosystème Sirius/EMF. Dans SmartEA, AQL sert :

| Usage | Exemple |
|---|---|
| **Requêtes ad hoc** | Trouver tous les `ApplicationComponent` dont l'owner est `<équipe>` |
| **Attributs dérivés** | Calculer une criticité dérivée des relations |
| **Services AQL custom** | Exposer une fonction métier `myCustomService(self)` accessible depuis diagrammes et tableaux |
| **Validation contraintes** | Vérifier des règles de cohérence du modèle |

> *"Extensive query capabilities including date manipulation, derived attributes, and semantic analysis functions"* — services AQL custom possibles [📖²](https://www.obeosoft.com/en/products/smartea/changelog "Obeo SmartEA — Changelog, capacités AQL étendues")
>
> *En français* : **capacités de requête étendues** — manipulation de dates, attributs dérivés, fonctions d'analyse sémantique. Les services AQL custom sont possibles.

### Exemple : compter les applications par tier

```aql
self.eAllContents()->select(e | e.oclIsKindOf(archimate::ApplicationComponent))
   ->groupBy(c | c.properties->select(p | p.key = 'tier').value)
```

Pattern : exposer ce résultat comme un **dashboard** dans SmartEA → les architectes voient en temps réel la répartition de leur catalogue applicatif par tier.

## Métamodèle modifiable

> *"Tailor, when necessary, the data connectors, the views and the metamodel that Obeo SmartEA delivers"* [📖³](https://www.obeosoft.com/en/products/smartea/ "Obeo SmartEA — Product, métamodèle modifiable")
>
> *En français* : **adapter, si nécessaire, les connecteurs, les vues et le métamodèle** livrés par SmartEA.

L'héritage Sirius/EMF permet :
- Ajouter des **attributs custom** sur les concepts ArchiMate standards (ex : ajouter un attribut `tier` sur `ApplicationComponent`)
- Définir de **nouveaux concepts** non présents dans ArchiMate standard (ex : `ChainOfValue` propre au métier)
- Créer des **viewpoints** custom (vues spécialisées d'un sous-ensemble du modèle)
- Adapter les **palettes graphiques** par viewpoint

⚠️ **Compromis** : étendre le métamodèle apporte de la souplesse mais éloigne du standard. Si on partage la cartographie via Open Exchange File Format (XMI standard), les extensions custom risquent d'être perdues. Bonne pratique : extensions limitées, documentées, traçables.

## Recherche LLM — pattern et garde-fous

> *"Natural language search generating AQL queries via large language models"* (beta v8.2.0) [📖²](https://www.obeosoft.com/en/products/smartea/changelog "Obeo SmartEA — Changelog, recherche LLM v8.2.0")
>
> *En français* : **recherche en langage naturel via LLM** — la requête est traduite en AQL puis exécutée.

### Garde-fous à mettre en place

L'intégration LLM dans SmartEA est en **beta** — quelques points à clarifier avant déploiement :

| Question | Pourquoi c'est important |
|---|---|
| **Qui héberge le LLM ?** Cloud public ? Gateway interne ? | Conformité RGPD si le repo contient des données sensibles |
| **Quel coût par requête ?** | Budget OPEX — la recherche LLM peut être appelée fréquemment |
| **Quelle gouvernance des prompts ?** | Audit, conformité, traçabilité |
| **Quel filtrage PII** sur les modèles avant envoi au LLM ? | Le repo EA peut contenir des noms de personnes (`BusinessActor`) |
| **Mode advisory only ou exécution automatique ?** | L'AQL généré peut-il modifier le modèle, ou seulement le requêter ? |

Pattern recommandé (aligné avec la doctrine [LLM as SRE Advisor](../../sre/guides/llm-as-sre-advisor.md "KB SRE — LLM as SRE Advisor, pattern advisory only")) : **advisory only** — le LLM génère l'AQL, l'utilisateur le **valide** avant exécution. Pas de chaîne *« prompt → AQL → exécution → modification »* sans humain dans la boucle.

## Catalogue de connecteurs natifs — état réel

> ⚠️ **Pas de catalogue documenté publiquement** des connecteurs natifs vers Confluence / JIRA / ServiceNow / webhooks.

Ce que la doc publique mentionne explicitement :
- ✅ **Excel** import/export (objets + relations)
- ✅ **Logs applicatifs** via APIs ouvertes
- ✅ **CMDB / repositories d'infrastructure** via APIs ouvertes
- ✅ **M2Doc** export Word
- ✅ **OMG BPMN2 XML** export
- ⚠️ Confluence / JIRA / ServiceNow / GitLab : **non documentés** publiquement → à construire via APIs ouvertes ou à demander à Obeo

Cela peut sembler limité face à [LeanIX](https://www.leanix.net/ "LeanIX — large catalogue de connecteurs SaaS") qui a un large catalogue de connecteurs natifs. Le compromis SmartEA : **APIs ouvertes flexibles**, mais à construire soi-même.

## Plugins / extensions

L'héritage Eclipse permet en théorie d'écrire des **plugins Eclipse** côté client lourd qui étendent SmartEA. C'est rarement documenté pour des extensions tierces — on est dans une zone *« contactez Obeo pour vos besoins spécifiques »*.

Côté web (Sirius Web), la stack React + GraphQL + Spring permet d'imaginer des extensions modernes — mais sans pattern d'extensibilité documenté publiquement.

## Cheatsheet — exemples d'automatisation

```bash
# Pseudo-script d'import Excel via web service stéréotypé (pattern indicatif)
curl -X POST -H "Authorization: Bearer <token>" \
     -F "file=@catalogue.xlsx" -F "stereotype=ApplicationComponent" \
     "https://<smartea-host>/api/import/xlsx"

# Pseudo-export en Excel
curl -X GET -H "Authorization: Bearer <token>" \
     -o export.xlsx \
     "https://<smartea-host>/api/export/xlsx?type=ApplicationComponent"
```

> ⚠️ Endpoints réels à valider avec la doc API officielle Obeo (non publique en source ouverte).

## Liens

- [`architecture.md`](architecture.md) — Stack technique (Sirius Web, GraphQL)
- [`repository.md`](repository.md) — Capacités du repo et imports
- [`sre-link.md`](sre-link.md) — Consommer le repo SmartEA depuis un outil SRE externe
