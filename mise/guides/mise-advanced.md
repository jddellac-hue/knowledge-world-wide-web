# mise — Référence avancée

## Arguments de tasks (usage field)

Méthode recommandée pour déclarer les arguments d'une task :

```toml
[tasks.deploy]
usage = '''
arg "<environment>" help="Target environment" {
  choices "dev" "staging" "prod"
}
flag "-f --force" help="Force deploy"
flag "-v --verbose" help="Enable verbose output"
'''
run = '''
#!/usr/bin/env bash
set -euo pipefail
echo "Deploying to ${usage_environment}"
if [[ "${usage_force:-false}" == "true" ]]; then
  echo "FORCE mode"
fi
'''
```

Les arguments deviennent des variables d'environnement avec le préfixe `usage_` :
- `--dry-run` → `$usage_dry_run`
- `<environment>` → `$usage_environment`

Pour les tasks file-based, utiliser `#USAGE` :
```bash
#!/usr/bin/env bash
#MISE description="Build the project"
#USAGE flag "-c --clean" help="Clean before building"
#USAGE flag "-p --profile <profile>" help="Build profile" default="debug"
#USAGE arg "<target>" help="Build target"
```

## Sources et outputs (caching)

```toml
[tasks.build]
run = "cargo build"
sources = ["Cargo.toml", "src/**/*.rs"]
outputs = ["target/debug/myapp"]
```

Si les outputs sont plus récents que les sources, la task est **skippée**.
`outputs = { auto = true }` pour du tracking interne (stocké dans `~/.local/state/mise/task-outputs/`).

## Dépendances avancées

```toml
[tasks.ci]
depends = ["lint", "test"]          # exécutées AVANT, échec = stop
depends_post = ["cleanup"]          # exécutées APRÈS
wait_for = ["db-migrate"]           # attend si déjà en cours

# Avec args/env passés aux dépendances
[tasks.deploy]
depends = [
  { task = "build", args = ["--release"], env = { OPT = "1" } }
]
```

Les dépendances dupliquées ne s'exécutent qu'une fois. Pas de dépendances circulaires.

## Exécution parallèle

```bash
mise run lint ::: test ::: typecheck    # 3 tasks en parallèle
mise run "test:*"                       # wildcard
mise run                                # sélecteur interactif
```

Jobs parallèles : 4 par défaut, configurable via `--jobs`, `MISE_JOBS`, ou settings.

## mise watch

Nécessite watchexec : `mise use -g watchexec@latest`

```bash
mise watch build                        # surveille les sources de la task
mise watch build --watch src --exts rs  # surveillance custom
mise watch serve --restart              # redémarre le process
```

## Variables d'environnement fournies aux tasks

| Variable | Description |
|----------|-------------|
| `MISE_ORIGINAL_CWD` | Répertoire de travail initial |
| `MISE_CONFIG_ROOT` | Répertoire contenant mise.toml |
| `MISE_PROJECT_ROOT` | Racine du projet |
| `MISE_TASK_NAME` | Nom de la task en cours |
| `MISE_TASK_DIR` | Répertoire du script de la task |
| `MISE_TASK_FILE` | Chemin complet du script |

## Profils d'environnement (MISE_ENV)

```bash
MISE_ENV=development    # charge mise.development.toml
MISE_ENV=ci,test        # multiples envs, le dernier gagne
```

Priorité de chargement :
1. `mise.{MISE_ENV}.local.toml`
2. `mise.local.toml`
3. `mise.{MISE_ENV}.toml`
4. `mise.toml`

## Environment avancé

```toml
[env]
# Chargement de fichiers .env
_.file = ".env"
_.file = [".env", { path = ".secrets", redact = true }]

# Ajout au PATH
_.path = ["./bin", "./node_modules/.bin"]

# Sourcer un script bash
_.source = "./load-env.sh"

# Créer un venv Python automatiquement
_.python.venv = { path = ".venv", create = true }

# Variables requises (échec si absentes)
DATABASE_URL = { required = true, help = "Connection string needed" }

# Masquage dans les logs
SECRET_KEY = { value = "abc123", redact = true }
```

## Tera templates

Disponible dans les valeurs de config. Délimiteurs : `{{ }}` expressions, `{% %}` statements.

Variables : `env`, `cwd`, `config_root`, `mise_bin`, `mise_pid`, `tools`.
Fonctions : `exec()`, `arch()`, `os()`, `num_cpus()`, `now()`, `read_file()`.

**Échapper les `{{ }}` littéraux** (Helm, Jinja, Go templates) :
```toml
[env]
MY_TEMPLATE = "{% raw %}{{ .Values.name }}{% endraw %}"
```

## Répertoire de travail par défaut

Les tasks s'exécutent dans `{{ config_root }}` (le dossier contenant mise.toml), **PAS** dans le cwd de l'utilisateur. Utiliser `dir = "{{cwd}}"` pour exécuter depuis le cwd de l'utilisateur. Accéder au cwd original via `$MISE_ORIGINAL_CWD`.

## Gotchas supplémentaires

- **Les dépendances n'héritent PAS de `env`** — chaque task a son propre scope
- **Tasks file-based : chmod +x obligatoire** — oubli fréquent
- **`arg()`, `option()`, `flag()` dans run** — DEPRECATED (suppression 2026.11.0), migrer vers `usage`
- **`mise <task>` en raccourci** — éviter dans les scripts (peut confliter avec les commandes futures), préférer `mise run <task>`
- **Go templates dans les tâches TOML** : le moteur Tera interprète `{{ }}` comme ses propres templates. Les commandes contenant `{{.Name}}` (Docker, Helm, Go) doivent être externalisées dans des scripts bash séparés ou les accolades escapées via `{% raw %}...{% endraw %}`.
- **Processus background dans les tâches TOML** : les commandes terminées par `&` ou `nohup` peuvent causer un exit code 144 (signal SIGTERM) quand mise gère son propre cycle de vie. Externaliser les processus longs dans des scripts bash dédiés.
- **TOML triple-quotes et backslash** : les chaînes `"""` interprètent `\"` et `\n`. Pour du code Python ou des commandes avec antislashs, préférer des scripts externes ou des chaînes `'''` (littérales).
