# Mise à jour des variables GitLab via JSON + curl

Voici une solution complète basée sur un fichier JSON, plus robuste pour gérer les caractères spéciaux, les valeurs multilignes et les types de variables.

## 📄 Format du fichier JSON

Créez un fichier `variables.json` :

```json
[
  {
    "key": "API_KEY",
    "value": "abc123secret",
    "protected": false,
    "masked": true,
    "environment_scope": "*"
  },
  {
    "key": "DB_HOST",
    "value": "db.example.com",
    "protected": false,
    "masked": false,
    "environment_scope": "*"
  },
  {
    "key": "DB_PASSWORD",
    "value": "p@ssw0rd!",
    "protected": true,
    "masked": true,
    "environment_scope": "production"
  }
]
```

**Champs disponibles :**

| Champ | Requis | Description |
|-------|--------|-------------|
| `key` | ✅ | Nom de la variable |
| `value` | ✅ | Valeur |
| `protected` | ❌ | Réservée aux branches/tags protégés |
| `masked` | ❌ | Masquée dans les logs (nécessite des règles de format) |
| `environment_scope` | ❌ | Portée (par défaut `*`) |
| `variable_type` | ❌ | `env_var` (défaut) ou `file` |

## 🛠️ Script bash avec `jq`

```bash
#!/bin/bash
set -euo pipefail

# Configuration
GITLAB_URL="https://gitlab.example.com"
PROJECT_ID="123"
TOKEN="votre_token_personnel"
FICHIER="variables.json"

# Vérifier les dépendances
command -v jq >/dev/null || { echo "jq est requis"; exit 1; }
command -v curl >/dev/null || { echo "curl est requis"; exit 1; }

# Nombre de variables à traiter
TOTAL=$(jq length "$FICHIER")
echo "→ $TOTAL variable(s) à traiter"

# Itération sur chaque entrée du tableau JSON
jq -c '.[]' "$FICHIER" | while read -r item; do
  KEY=$(echo "$item"    | jq -r '.key')
  VALUE=$(echo "$item"  | jq -r '.value')
  PROTECTED=$(echo "$item" | jq -r '.protected // false')
  MASKED=$(echo "$item"    | jq -r '.masked // false')
  SCOPE=$(echo "$item"     | jq -r '.environment_scope // "*"')
  TYPE=$(echo "$item"      | jq -r '.variable_type // "env_var"')

  echo "→ Mise à jour de $KEY (scope=$SCOPE)..."

  # Encodage URL du scope et de la clé
  KEY_ENC=$(jq -rn --arg v "$KEY"   '$v|@uri')
  SCOPE_ENC=$(jq -rn --arg v "$SCOPE" '$v|@uri')

  # Tentative de mise à jour (PUT)
  HTTP_CODE=$(curl --silent --output /tmp/gitlab_resp.json --write-out "%{http_code}" \
    --request PUT \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --header "Content-Type: application/json" \
    --data "$(jq -n \
        --arg v "$VALUE" \
        --argjson p "$PROTECTED" \
        --argjson m "$MASKED" \
        --arg t "$TYPE" \
        '{value: $v, protected: $p, masked: $m, variable_type: $t}')" \
    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/variables/$KEY_ENC?filter[environment_scope]=$SCOPE_ENC")

  # Si la variable n'existe pas (404), on la crée (POST)
  if [ "$HTTP_CODE" = "404" ]; then
    echo "  ↳ inexistante, création..."
    HTTP_CODE=$(curl --silent --output /tmp/gitlab_resp.json --write-out "%{http_code}" \
      --request POST \
      --header "PRIVATE-TOKEN: $TOKEN" \
      --header "Content-Type: application/json" \
      --data "$(jq -n \
          --arg k "$KEY" \
          --arg v "$VALUE" \
          --arg s "$SCOPE" \
          --argjson p "$PROTECTED" \
          --argjson m "$MASKED" \
          --arg t "$TYPE" \
          '{key: $k, value: $v, environment_scope: $s, protected: $p, masked: $m, variable_type: $t}')" \
      "$GITLAB_URL/api/v4/projects/$PROJECT_ID/variables")
  fi

  # Vérification du résultat
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "  ✅ OK ($HTTP_CODE)"
  else
    echo "  ❌ Échec ($HTTP_CODE)"
    cat /tmp/gitlab_resp.json
    echo ""
  fi
done
```

## 🔑 Points clés de cette approche

**1. Le champ `environment_scope` est un paramètre de requête, pas du body**

L'API GitLab attend le scope dans l'URL pour identifier la variable à mettre à jour :

```
PUT /projects/:id/variables/:key?filter[environment_scope]=production
```

C'est une source fréquente d'erreur.

**2. Fallback automatique PUT → POST**

Si la variable n'existe pas, le `PUT` renvoie `404`. On bascule alors sur un `POST` pour la créer.

**3. Encodage URL avec `jq @uri`**

Les noms de variables ou scopes contenant des caractères spéciaux (espaces, `/`, etc.) sont correctement encodés.

**4. Gestion des types avec `jq -n`**

On construit le payload JSON dynamiquement, en préservant les types (`--argjson` pour les booléens, `--arg` pour les chaînes). Cela évite les injections et les erreurs de quoting.

**5. Valeurs multilignes**

Puisque le JSON autorise les `\n`, une valeur comme `"ligne1\nligne2"` sera transmise correctement, contrairement à un CSV.

## 🚀 Utilisation

```bash
chmod +x update_variables.sh
./update_variables.sh
```

## 🧪 Test rapide avec un seul élément

Pour valider avant de tout lancer :

```bash
jq '.[0]' variables.json | curl --request PUT \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --header "Content-Type: application/json" \
  --data @- \
  "$GITLAB_URL/api/v4/projects/$PROJECT_ID/variables/$(jq -r '.[0].key' variables.json)"
```

## ⚠️ Notes sur le masquage (`masked: true`)

GitLab refuse le masquage si la valeur ne respecte pas certains critères (au moins 8 caractères, pas de `$`, `\n`, etc.). Si vous obtenez une erreur `400`, désactivez `masked` ou adaptez la valeur.

## 🔄 Alternative : `glab` CLI

Si vous avez le CLI officiel GitLab, la commande est plus simple :

```bash
jq -c '.[]' variables.json | while read -r v; do
  key=$(echo "$v" | jq -r '.key')
  glab variable set "$key" "$(echo "$v" | jq -r '.value')" \
    --masked="$(echo "$v" | jq -r '.masked // false')" \
    --protected="$(echo "$v" | jq -r '.protected // false')" \
    --scope="$(echo "$v" | jq -r '.environment_scope // "*"')"
done
```

Cette version délègue toute la logique API au CLI, ce qui évite les pièges de l'API REST brute.
