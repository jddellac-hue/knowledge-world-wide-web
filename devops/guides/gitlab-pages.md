---
name: gitlab-pages
description: Visibilité GitLab Pages, vérification API hors UI, alternative artifacts CI quand on doute. Le pages_access_level hérite de la visibility du projet — un projet privé sert ses Pages uniquement aux membres. Réponse aux questions « est-ce que mes Pages sont publiques ? » et « comment vérifier sans interface admin ? ».
---

# GitLab Pages — visibilité et vérification

[GitLab Pages](https://docs.gitlab.com/ee/user/project/pages/) sert un site statique généré par CI. Sa visibilité est **dérivée de la visibilité du projet**, mais peut être réglée plus restrictivement via `pages_access_level`. Ce guide explique le couplage et donne les commandes pour vérifier hors interface admin.

---

## Le couplage `visibility` × `pages_access_level`

Tout projet GitLab a deux paramètres qui contrôlent l'accès aux Pages :

| Paramètre | Valeurs | Effet |
|---|---|---|
| `visibility` | `private` / `internal` / `public` | Visibilité du projet lui-même |
| `pages_access_level` | `disabled` / `private` / `enabled` / `public` | Visibilité des Pages déployés |

Le résultat **réel** se calcule par intersection :

| visibility | pages_access_level | Pages servis à |
|---|---|---|
| `private` | `enabled` | **Membres du projet uniquement** (pas l'instance, pas le public) |
| `private` | `private` | Membres du projet uniquement (équivalent) |
| `internal` | `enabled` | Tous les utilisateurs authentifiés de l'instance |
| `public` | `enabled` | **Public internet** |
| toute valeur | `disabled` | 404 — Pages désactivés |
| toute valeur | `public` | Public internet (override la visibilité projet — à éviter) |

**Règle clé** : un projet `private` avec `pages_access_level: enabled` reste privé — les Pages sont accessibles **uniquement aux membres du projet**, jamais publiques. C'est la configuration sûre par défaut.

---

## Vérifier la visibilité sans accès admin

Si on n'a pas d'accès admin GitLab, l'API REST avec un PAT non-admin suffit :

```bash
curl --silent \
  --header "PRIVATE-TOKEN: <pat>" \
  "https://<gitlab-host>/api/v4/projects/<id-or-namespace-encoded>" | \
  jq '{visibility, pages_access_level: .pages_access_level, web_url}'
```

Sortie attendue pour un projet privé avec Pages activés :

```json
{
  "visibility": "private",
  "pages_access_level": "enabled",
  "web_url": "https://<gitlab-host>/<group>/<project>"
}
```

> ⚠️ L'endpoint admin `/admin/projects/:id` renvoie **403** sans rôle admin. L'endpoint user `/projects/:id` suffit pour `visibility` et `pages_access_level`.

---

## Alternative 100 % sûre — artifacts CI

Quand on doute de la config Pages ou qu'on veut **garantir** la non-publication, publier en **artifact CI** plutôt que Pages :

```yaml
build-doc:
  stage: build
  script:
    - mdbook build
  artifacts:
    paths:
      - book/
    expire_in: 30 days
```

Les artifacts CI :
- **Jamais public** (toujours liés à la visibilité du projet, comme la CI)
- Téléchargeables par les membres via UI ou API
- Limite : pas de URL navigable type `<group>.gitlab.io/<project>` — il faut télécharger le ZIP et le servir localement

**Quand préférer artifact** : doc interne avec données sensibles, projet où l'audit Pages n'a pas été fait, ou projet `internal` où on veut limiter aux membres et pas à toute l'instance.

---

## Anti-patterns

| Anti-pattern | Conséquence |
|---|---|
| `visibility: public` + `pages_access_level: private` | Le projet reste public en lecture (code visible), seuls les Pages sont restreints. Souvent l'inverse de l'intention. |
| Mettre des données sensibles dans un repo `internal` avec Pages activés | Toute personne authentifiée sur l'instance lit le contenu, même hors équipe. Préférer `private`. |
| Compter sur `pages_access_level: public` pour exposer publiquement un projet privé | Cas non documenté, à éviter — préférer rendre le projet public ou utiliser un autre canal de publication. |

---

## Cheatsheet — commandes

```bash
# Lire la config d'un projet
curl -sH "PRIVATE-TOKEN: <pat>" \
  "https://<gitlab-host>/api/v4/projects/<group>%2F<project>" | \
  jq '{visibility, pages_access_level}'

# URL Pages déployés (si visibility le permet)
echo "https://<group>.<gitlab-pages-host>/<project>"

# Désactiver Pages d'un projet (admin ou owner)
curl -X PUT -H "PRIVATE-TOKEN: <pat>" \
  -d "pages_access_level=disabled" \
  "https://<gitlab-host>/api/v4/projects/<id>"
```

---

## Liens

- Doc officielle : https://docs.gitlab.com/ee/user/project/pages/pages_access_control.html
- API Projects : https://docs.gitlab.com/ee/api/projects.html
