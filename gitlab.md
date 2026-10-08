# 📋 Lister les membres et rôles d'un projet/groupe GitLab

## 🔑 Prérequis

- Un **token d'accès personnel** GitLab avec le scope `api`
- L'**ID** (numérique) ou le **chemin encodé** du projet/groupe

---

## 🚀 Commandes `curl`

### 1️⃣ Projet — membres directs

```bash
curl --header "PRIVATE-TOKEN: <VOTRE_TOKEN>" \
  "https://gitlab.example.com/api/v4/projects/<ID_PROJET>/members"
```

### 2️⃣ Projet — membres avec héritage (recommandé)

```bash
curl --header "PRIVATE-TOKEN: <VOTRE_TOKEN>" \
  "https://gitlab.example.com/api/v4/projects/<ID_PROJET>/members/all"
```

### 3️⃣ Groupe — membres directs

```bash
curl --header "PRIVATE-TOKEN: <VOTRE_TOKEN>" \
  "https://gitlab.example.com/api/v4/groups/<ID_GROUPE>/members"
```

### 4️⃣ Groupe — membres avec héritage (recommandé)

```bash
curl --header "PRIVATE-TOKEN: <VOTRE_TOKEN>" \
  "https://gitlab.example.com/api/v4/groups/<ID_GROUPE>/members/all"
```

> 💡 **Chemin encodé** : pour un projet `mon-groupe/mon-projet`, utilisez `mon-groupe%2Fmon-projet`.

---

## 📊 Correspondance `access_level` → Rôle

| `access_level` | Rôle |
| :---: | :--- |
| 10 | Guest |
| 20 | Reporter |
| 30 | Developer |
| 40 | Maintainer |
| 50 | Owner |

---

## 📄 Exemple de réponse JSON

```json
[
  {
    "id": 1,
    "username": "raymond_smith",
    "name": "Raymond Smith",
    "access_level": 30
  },
  {
    "id": 2,
    "username": "john_doe",
    "name": "John Doe",
    "access_level": 40
  }
]
```

➡️ `raymond_smith` = **Developer** (30)
➡️ `john_doe` = **Maintainer** (40)

---

## 🎯 Formatage rapide avec `jq`

### Afficher uniquement `nom → rôle`

```bash
curl -s --header "PRIVATE-TOKEN: <VOTRE_TOKEN>" \
  "https://gitlab.example.com/api/v4/projects/<ID_PROJET>/members/all" \
| jq -r '.[] | "\(.name) → \(.access_level)"'
```

### Filtrer uniquement les Maintainers (niveau 40)

```bash
curl -s --header "PRIVATE-TOKEN: <VOTRE_TOKEN>" \
  "https://gitlab.example.com/api/v4/projects/<ID_PROJET>/members/all" \
| jq -r '.[] | select(.access_level == 40) | .name'
```

### Convertir le niveau en libellé lisible

```bash
curl -s --header "PRIVATE-TOKEN: <VOTRE_TOKEN>" \
  "https://gitlab.example.com/api/v4/projects/<ID_PROJET>/members/all" \
| jq -r '
  def role:
    {10:"Guest",20:"Reporter",30:"Developer",40:"Maintainer",50:"Owner"}[.];
  .[] | "\(.name) (\(.username)) → \(.access_level | role)"
'
```

---

## ⚙️ Options utiles

| Option | Description |
| :--- | :--- |
| `?per_page=100&page=1` | Contrôle de la pagination |
| `?query=dupont` | Filtre par nom/username |
| `/all` en fin d'URL | Inclut les membres hérités des groupes parents |

---

## 🧰 Alternatives

- **GitLab CLI (`glab`)** : interface en ligne de commande officielle
- **Bibliothèques** : `python-gitlab`, `go-gitlab`, module PowerShell `GitLabAPI`
- **Interface Web** : `Projet → Manage → Members` ou `Groupe → Manage → Members`
