# Git — refactos d'historique, migrations « sans historique », vérif déterministe

> Leçons vécues sur des refactos multi-repos (consolidation, scission, migration
> de forge, purge de contenu sensible). Génériques, applicables à tout repo.

## 1. `git rm` dans une refacto ne purge PAS l'historique

**Contexte** : on « nettoie » un repo en retirant des fichiers (commit `remove`),
puis on le croit propre / agnostique.

**Observation** : un contenu retiré du *working tree* reste **intégralement
récupérable dans l'historique** (`git log`, `git show <ancien-commit>`). Un audit
qui ne scanne que le working tree conclut « propre » à tort.

**Cause** : `git rm` ajoute un commit de suppression ; il ne réécrit pas les blobs
des commits antérieurs.

**Résolution** :
```bash
# Auditer TOUT l'historique, pas le working tree
git grep -nIiE '<motif-sensible>' $(git rev-list --all) -- '<path>'
```
Pour purger réellement : réécriture d'historique (`git filter-repo`, ou
ré-initialisation en commit racine) **puis** `git push --force`. Vérifier ensuite
`git grep ... $(git rev-list --all)` → vide.

## 2. Migration « sans historique » FIDÈLE : `--orphan`, pas `init + add -A`

**Contexte** : recréer un repo en un seul commit racine (perte d'historique
voulue) tout en gardant **exactement** le contenu tracké.

**Observation** : `git init` + `git add -A` sur l'arbre **perd les fichiers
tracés-mais-gitignorés** (un fichier commité puis ajouté plus tard au
`.gitignore` reste tracké, mais `add -A` dans un repo neuf ne le ré-ajoute pas).
Constaté : 71 fichiers tracés source → 68 après `init+add -A` (3 perdus
silencieusement).

**Résolution** : depuis un clone fidèle, `git checkout --orphan <b>` conserve
l'index (donc l'ensemble tracké **exact**) ; `git commit` committe ces fichiers
sans dépendre du `.gitignore`. Transport via `git bundle` si la cible est sur une
autre forge/réseau.
```bash
git checkout --orphan _mig && git commit -m "import (historique réinitialisé)"
git bundle create repo.bundle _mig          # NB : `git bundle` n'a pas d'option -q
```

## 3. `git push` imprime l'URL du remote sur **stderr**

**Contexte** : pilotage d'un push par un outil/agent qui capture la sortie.

**Observation** : `git push` écrit `To https://<host>/<path>.git` sur **stderr**.
Si l'URL du remote est sensible (forge interne, structure privée), elle entre
dans les logs / le contexte de l'appelant.

**Résolution** : `git push … >/dev/null 2>&1` quand l'URL ne doit pas fuiter ;
**vérifier le push autrement** (cf. §4), jamais via la sortie de `push`.

## 4. Discipline « miroir vérifié AVANT suppression » + ne pas croire les « OK »

**Contexte** : migration avec suppression de la source après copie ; orchestration
par un outil/sous-agent qui rapporte « OK ».

**Observation** : les rapports d'outils/agents (« push OK », « cloné », « absent »)
sont **non fiables** — faux positifs (succès rapporté, rien poussé) **et** faux
négatifs. Un `clone` frais peut sembler vide alors que le contenu est sur une
branche non-défaut (HEAD distant ≠ `main`).

**Résolution** : avant toute suppression irréversible (`gh repo delete`,
`rm -rf`), **prouver déterministiquement** que la cible est durable :
```bash
git ls-tree -r --name-only origin/main -- <path> | wc -l   # == compte source ?
git ls-remote --symref origin HEAD                          # branche défaut == main ?
```
Gate strict : **pas de delete tant que `compte_remote == compte_source` non prouvé
en métadonnées** (pas via le dire de l'outil). Conserver un `git bundle --all` de
secours jusqu'à confirmation.

## 5. Règle générale

> Toute opération git **destructive ou sortante** se valide sur **l'artefact réel**
> (refs distantes, comptes de fichiers, `rev-list --all`), **jamais** sur le
> rapport de l'outil/agent qui l'a exécutée. Vérifier *avant* l'irréversible.
