# Concourse — Opérations et Incidents

> Référence opérationnelle : fly CLI, debugging, incidents connus (ATC restart, K8s credentials).
> Pour l'écriture de pipelines YAML, voir [`pipelines.md`](pipelines.md).

---

## 1. fly CLI — Commandes essentielles

| Commande | Usage |
|----------|-------|
| `fly login` | Connexion à un target |
| `fly set-pipeline` (`sp`) | Créer/mettre à jour un pipeline |
| `fly destroy-pipeline` (`dp`) | Supprimer un pipeline |
| `fly get-pipeline` (`gp`) | Afficher le YAML d'un pipeline |
| `fly validate-pipeline` (`vp`) | Valider un YAML localement |
| `fly trigger-job` (`tj`) | Déclencher un job manuellement |
| `fly pause-job` / `unpause-job` | Pause/reprise d'un job |
| `fly pause-pipeline` / `unpause-pipeline` | Pause/reprise d'un pipeline |
| `fly expose-pipeline` | Rendre un pipeline public |
| `fly intercept` | SSH dans un container en cours |
| `fly execute` | Exécuter une task localement |
| `fly watch` | Suivre les logs d'un build |
| `fly builds` | Lister les builds récents |
| `fly workers` | Lister les workers |
| `fly prune-worker` | Nettoyer un worker fantôme |
| `fly check-resource` | Forcer un check de resource |
| `fly pin-resource` | Figer une resource à une version |

---

## 2. Incidents connus

### Restart de l'ATC — ressources bloquées

Après un redémarrage de l'ATC (web), les versions des ressources sont **perdues en mémoire**. Les builds qui attendent des inputs (`get:` avec `passed:` ou `trigger: true`) restent indéfiniment en état "pending" sans message d'erreur clair.

**Diagnostic** : l'API de préparation de build révèle la cause réelle :
```bash
fly -t ci curl /api/v1/builds/{build-id}/preparation
# → "missing_input_reasons": {"my-resource": "latest version of resource not found"}
```

**Résolution** : relancer un check sur les ressources bloquées :
```bash
fly -t ci check-resource -r pipeline/resource-name
# Pour toutes les ressources git après un restart :
for r in source-code config infra; do
  fly -t ci check-resource -r my-pipeline/$r
done
```

Si le check échoue avec "credential not found", le credential manager (K8s/Vault/Conjur) n'a pas le secret correspondant → créer le secret puis re-checker.

### Credential manager K8s — secrets manquants

Avec le credential manager Kubernetes, les secrets se trouvent dans le namespace `concourse-{team}` (ex: `concourse-main`). Un secret manquant bloque les checks de ressource silencieusement.

```bash
# Créer un secret manquant (team-scoped) :
kubectl -n concourse-main create secret generic my-var --from-literal=value="my-value"
# Ou (pipeline-scoped) :
kubectl -n concourse-main create secret generic my-pipeline-my-var --from-literal=value="my-value"
```

Les `-l vars.yml` passés à `fly set-pipeline` n'affectent que l'interpolation au moment du set-pipeline. Les task files sont interpolés au runtime par le credential manager. Si une variable est dans un task file mais pas dans K8s → error à l'exécution.

---

## 3. Debugging

```bash
# Shell interactif dans un container en cours
fly -t <target> intercept -b <build-id> -s <step-name>

# Suivre les logs d'un build
fly -t <target> watch -j <pipeline>/<job>
fly -t <target> watch -b <build-id>

# Exécuter une task en isolation (sans pipeline)
fly -t <target> execute -c task.yml -i input=./local-dir

# Forcer la détection d'un nouveau commit
fly -t <target> check-resource -r <pipeline>/<resource>

# Valider un pipeline YAML localement
fly -t <target> validate-pipeline -c pipeline.yml

# Trouver les builds en cours ou en attente
fly -t <target> builds -p <pipeline> | grep -E "started|pending"

# Préparer un build bloqué — diagnostic
fly -t <target> curl /api/v1/builds/<build-id>/preparation
```

> Pour le pattern `fly execute` et le harness de test, voir la section **Tests unitaires des tasks** dans le [`README.md`](../README.md).

---

## Journal des mises à jour

| Date | Changement |
|------|-----------|
| 2026-04-20 | Création — contenu extrait de `03-referentiel-expert.md` (fly CLI §9) et `concourse-advanced.md` (ops/incidents) |
