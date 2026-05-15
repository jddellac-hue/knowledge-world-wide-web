# GitHub Copilot CLI — leçons vécues

Capitalisation 2026-05-15 d'un onboarding Copilot CLI sur poste Linux <entreprise> avec compte entreprise. Couvre installation, auth OAuth device flow, et pilotage par SSH non-interactif (cas typique : pilotage par un autre agent IA).

## Installation sans sudo

Le poste cible n'a pas de Node préinstallé et l'utilisateur n'a pas sudo. Utiliser `nvm` :

```bash
curl -sSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.nvm/nvm.sh
nvm install 22         # Node ≥22 requis par @github/copilot
npm install -g @github/copilot
copilot --version      # → 1.0.x
```

`@github/copilot` (npm) remplace l'ancien `gh-copilot` (extension `gh`). Le CLI est entièrement standalone, pas besoin de `gh` installé.

## Authentification OAuth device flow

```bash
copilot login
# affiche un code XXXX-XXXX + URL https://github.com/login/device
```

⚠️ **Compte multi-org** : avant de coller le code dans le navigateur, vérifier qu'on est connecté au **compte qui porte la licence Copilot Business** (souvent compte entreprise distinct du perso). Switch via avatar GitHub → "Switch account".

⚠️ **SSO entreprise** : si l'orga a SSO activé, après autorisation initiale, ajouter une étape "Configure SSO" sur le token créé pour l'autoriser sur l'orga.

Le token est stocké dans le **système keychain** (`gnome-keyring` sur Linux desktop via Secret Service / libsecret). Stockage en clair dans `~/.copilot/` **seulement si** aucun keychain dispo.

## Piège : SSH non-interactif ne trouve pas le token

Quand on lance `copilot` depuis une session SSH non-interactive (cas pilotage à distance), il échoue avec :

```
Error: No authentication information found.
```

**Cause** : Copilot CLI lit le token via Secret Service, qui dépend de D-Bus. En SSH non-interactif, `DBUS_SESSION_BUS_ADDRESS` est vide, donc pas d'accès au keyring.

**Fix** : exporter le bus D-Bus de la session utilisateur active :

```bash
ssh <host> "
  source ~/.nvm/nvm.sh
  export DBUS_SESSION_BUS_ADDRESS=\"unix:path=/run/user/\$(id -u)/bus\"
  export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\"
  copilot -p \"...\" --allow-all-tools --no-ask-user -s
"
```

Prérequis : un `gnome-keyring-daemon` doit tourner pour cet UID (vérifier `ps -u $(id -u) | grep keyring`). Sur poste headless, c'est lancé par PAM lors de la session interactive — il faut donc qu'une session ait été ouverte au moins une fois (login graphique ou TTY).

Alternative pour environnements 100% headless : fine-grained PAT GitHub avec scope `Copilot Requests` exporté en `COPILOT_GITHUB_TOKEN`. Moins pratique car le PAT doit être généré manuellement avec la bonne permission.

## Piège n°2 (le vrai) : login OAuth qui « saute » — pas un problème réseau

Symptôme en pilotage SSH : `Error: Authentication token found but could not be
validated` / `Failed to fetch OAuth user login: fetch failed` / `unexpected error`.

**Fausses pistes coûteuses** (vécu, ~plusieurs heures perdues) : on incrimine le
VPN, un proxy filtrant, le full-tunnel, l'init du shell… Toutes **erronées**.
Le `ip route` est identique interactif/non-interactif, le DNS résout : ce n'est
**pas** le réseau.

**Vraie cause** : le **token OAuth Copilot a expiré / « sauté »**. Rien d'autre.

**Leçon durable** : devant un échec d'authentification d'un outil, **refaire le
login AVANT toute théorie réseau**. Ne pas sur-analyser un symptôme trivial.

**Remédiation** : relancer le device flow et revalider côté navigateur :

```bash
ssh -tt <host> 'bash -lic "
  export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus
  export XDG_RUNTIME_DIR=/run/user/\$(id -u)
  export NVM_DIR=\$HOME/.nvm; . \$NVM_DIR/nvm.sh
  copilot login 2>&1
"'
# → affiche un code XXXX-XXXX : le saisir sur github.com/login/device
#   avec le compte qui porte la licence Copilot (+ Configure SSO si demandé)
# → 'Signed in successfully as <user>' = token renouvelé.
```

## Wrapper de pilotage SSH **validé**

Combinaison qui fonctionne de façon fiable (TTY + shell login interactif + D-Bus) :

```bash
ssh -tt <host> 'bash -lic "
  export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus
  export XDG_RUNTIME_DIR=/run/user/\$(id -u)
  export NVM_DIR=\$HOME/.nvm; . \$NVM_DIR/nvm.sh
  copilot --model gpt-4.1 -p \"...\" --allow-all-tools --no-ask-user -s
"'
```

- `ssh -tt` : force un pseudo-TTY (sans, le job-control casse / sortie perdue).
- `bash -lic` : shell **login + interactif** → charge l'env qui rend les
  endpoints GitHub joignables + le keychain accessible.
- Le message `Failed to connect to bus` résiduel est **inoffensif** (le
  `DBUS_SESSION_BUS_ADDRESS` exporté prend le relais pour le keychain).

> Un `ssh <host> 'cmd'` simple (non-interactif, non-login) **ne marche pas** :
> ni l'env réseau ni le keychain ne sont chargés.

## Mode non-interactif (`-p`)

Pour scripting :

```bash
copilot --model gpt-4.1 \
  -p "Run: python3 script.py" \
  --allow-all-tools \
  --no-ask-user \
  -s
```

Flags clés :
- `-p "..."` : un seul prompt puis exit (sinon démarre TUI interactive).
- `--allow-all-tools` : pas de prompt de confirmation par tool — **requis** en non-interactif.
- `--no-ask-user` : désactive l'outil `ask_user`, donc Copilot ne pose pas de question d'éclaircissement.
- `-s` (silent) : retire les stats, n'affiche que la réponse de l'agent.
- `--add-dir <path>` : autorise l'accès à un répertoire hors du CWD.

## Choix du modèle — doctrine de conso

`copilot --model <id>` accepte ces IDs (catalogue Copilot Business 2026-05) :

| Famille | IDs disponibles |
|---|---|
| Claude | `opus-4.7`, `opus-4.6`, `opus-4.5`, `sonnet-4.6`, `sonnet-4.5`, `haiku-4.5` |
| OpenAI | `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.3-codex`, `gpt-5.2`, `gpt-5.2-codex`, `gpt-5-mini`, `gpt-4.1` |

Politique conso (à appliquer selon licence) :

- **Défaut** : `gpt-4.1` (0 premium request sur Copilot Business — inclus illimité).
- **Si insuffisant** : `claude-haiku-4.5` (faible coût premium, ~0.33).
- **Exception sur confirmation** : `claude-sonnet-4.6` (1 premium request).
- **À éviter sans demande explicite** : `claude-opus-*`, `gpt-5.5/5.4/5.3-codex` (coût premium élevé).

Pour interroger la liste réelle dispo sur un compte donné :

```bash
copilot --model gpt-4.1 -p "List the exact AI model IDs available to me via --model. Format: one per line."
```

## Modèle par défaut

Sans `--model`, Copilot CLI choisit selon le routing GitHub interne. Observé en pratique : par défaut sur `claude-haiku-4.5`. Pour forcer le modèle gratuit, **toujours passer `--model gpt-4.1` explicitement**.

### Retour d'XP — comparatif 3 modèles sur tâche d'exécution déterministe

Tâche : lancer un script déterministe via `-p` non-interactif et restituer sa sortie.

- `gpt-4.1` (gratuit) — **fidèle**, restitue exactement. Choix optimal.
- `claude-haiku-4.5` (~0,1 %/run) — fidèle aussi, **identique à gpt-4.1 mais payant** : aucun gain, à éviter quand gpt-4.1 suffit.
- `gpt-5-mini` (gratuit) — **refus injustifié** (« I cannot assist with that request ») sur une tâche pourtant anodine. À proscrire pour l'orchestration/exécution.

Corollaire : pour déléguer l'**exécution** d'un script préparé en amont, `gpt-4.1` suffit et coûte 0. La fiabilité vient du **script déterministe**, pas du modèle — multiplier les modèles puissants n'aide pas, et certains (`gpt-5-mini`) refusent à tort. Après ~9 échecs de délégation « prompt → le modèle construit les commandes », le pattern gagnant est : **script déterministe écrit en amont + modèle qui ne fait que le lancer**.

> **Confirmé** : `gpt-5-mini` re-testé → **refus reproductible (2/2)**, systématique sur l'orchestration/exécution.

#### Stratégie modèle & fallback (recommandation)

- **Exécution déterministe** (lancer un script préparé en amont) : **1 seul appel `gpt-4.1`**. Pas de double appel — la redondance de modèles n'apporte rien quand le script est déterministe (`gpt-4.1` et `claude-haiku-4.5` donnent un résultat identique).
- **Fallback utile** : `gpt-4.1` (primaire, gratuit) → en cas d'échec *technique* réel → `claude-haiku-4.5` (~0,1 %/run, fiable). **Pas** de fallback vers `gpt-5-mini` (refuse l'orchestration).
- **Double appel / multi-modèle** : à réserver aux tâches de **jugement ou d'analyse ouverte** (2 avis indépendants ont de la valeur), jamais à l'exécution déterministe (gaspillage de conso sans gain).

## Wrapper local recommandé

```bash
# ~/.bashrc côté poste pilote
copilot-remote() {
  ssh <host> "
    source ~/.nvm/nvm.sh
    export DBUS_SESSION_BUS_ADDRESS=\"unix:path=/run/user/\$(id -u)/bus\"
    export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\"
    copilot --model \${COPILOT_MODEL:-gpt-4.1} -p \"\$1\" --allow-all-tools --no-ask-user -s
  "
}
```

Usage : `copilot-remote "résume-moi ce fichier..."`. Surcharge possible : `COPILOT_MODEL=claude-sonnet-4.6 copilot-remote "..."`.

## Liens

- Doctrine two-tier LLM advisory : `[sre/guides/signal-first-doctrine.md](../../sre/guides/signal-first-doctrine.md)`
- Spec MCP anonymizer middleware : `pseudonymizer-agent/docs/architecture/mcp-anonymizer-middleware-spec.md` (repo privé)
