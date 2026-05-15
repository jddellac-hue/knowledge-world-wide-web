# Angular 15 — Specifiques version

## Stack technique

| Composant | Version |
|-----------|---------|
| Angular | 15.2.10 |
| Node | 18.19.0 |
| TypeScript | ES2022 |
| Tests unit | Jest 29 + jest-preset-angular |
| Tests E2E | Cypress 12 |
| i18n | @ngx-translate/core 14 |
| Auth | <internal-auth-library> 1.2 + jwt-decode 4 |
| Linting | ESLint + @angular-eslint |

## Proxy dev vers backend

`proxy.conf.json` pour `ng serve` — reecrit les appels API vers le backend Quarkus :

```json
{
  "/<sn-code>": {
    "target": "http://localhost:8077",
    "secure": false,
    "changeOrigin": true,
    "pathRewrite": {
      "^/<sn-code>": "/<service-name>"
    }
  }
}
```

Le nginx Docker fait le meme rewrite via `proxy_pass`.

## Dev replacement

Remplacer le container nginx Docker par `ng serve` local :

```bash
mise dev-<code-angular>
# ou manuellement :
# docker compose stop <service-angular>
# cd <repo-angular> && npm start
```

- La task `dev-<code>` extrait `node_modules` depuis le stage builder Docker si `ng` est absent (layers en cache apres `mise stack`, quasi-instantane). Pas de `npm install` depuis le host (le registry npm PE peut etre indisponible)
- Hot reload automatique a chaque sauvegarde
- Le proxy redirige `/<sn-code>/*` vers le backend Quarkus (localhost:8077)
- Port 4200 identique au container nginx → les tests Behave/Playwright fonctionnent sans changement

## Build Docker

3 stages :
1. **npm config** : copie package.json, installe deps (avec bouchon `<internal-auth-library>`)
2. **Node build** : `npm run build` (Angular CLI prod)
3. **Nginx serve** : copie le `dist/` dans nginx, template de conf pour le reverse proxy

```dockerfile
FROM node:18.19.0-alpine AS builder
# ...
FROM nginx:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html/ihm-<service-name>
COPY nginx-spa.conf.template /etc/nginx/templates/spa.conf.template
```

## Bouchon authent

Le module `<internal-auth-library>` vient du registre npm PE interne (inaccessible en local). Un bouchon est copie manuellement dans `node_modules/<internal-auth-library>/` avant `npm install`.

## environment.ts et bouchon-<provider>

`ng serve` utilise `environment.ts` (dev), pas `environment.prod.ts` (Docker/dockerize). Pour que le flow OAuth fonctionne avec bouchon-<provider> en mode dev :

```typescript
// environment.ts
openAMUrl: 'http://localhost:9012',  // bouchon-<provider>, PAS le vrai SSO
```

Sans ca, l'iframe auth pointe vers le vrai SSO interne (`<sso-host>`) qui est inaccessible en local, et l'overlay de login couvre toute la page (z-index 9999).

## Points d'attention

- **baseHref** : `/ihm-<app>/` dans `angular.json` — toutes les routes sont prefixees
- **SPA routing** : nginx configure `try_files $uri $uri/ /ihm-<app>/index.html`
- **CORS** : le backend Quarkus autorise `*` (`quarkus.http.cors.origins=/.*/`)
