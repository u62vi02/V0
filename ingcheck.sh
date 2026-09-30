#!/bin/bash
# ingcheck.sh
# Rapport du nombre d'Ingress et d'HTTPRoute par namespace (uat/develop)

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Recherche des namespaces contenant 'uat' ou 'develop'...${NC}"
echo ""

# Récupérer les namespaces filtrés
namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -E 'uat|develop')

if [ -z "$namespaces" ]; then
    echo -e "${RED}Aucun namespace contenant 'uat' ou 'develop' trouvé${NC}"
    exit 0
fi

for ns in $namespaces; do
    ingress_count=$(kubectl get ingress -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    httproute_count=$(kubectl get httproute -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    [ -z "$ingress_count" ] && ingress_count=0
    [ -z "$httproute_count" ] && httproute_count=0

    if [ "$ingress_count" -eq 0 ] && [ "$httproute_count" -gt 0 ]; then
        status_icon="✅"
        status_text="${GREEN}OK: ingress=0 et httproute>0${NC}"
    elif [ "$ingress_count" -gt 0 ] && [ "$httproute_count" -gt 0 ]; then
        status_icon="⚠️"
        status_text="${YELLOW}ATTENTION: ingress>0 et httproute>0${NC}"
    elif [ "$ingress_count" -gt 0 ] && [ "$httproute_count" -eq 0 ]; then
        status_icon="❌"
        status_text="${RED}KO: ingress>0 et httproute=0${NC}"
    else
        status_icon="ℹ️"
        status_text="${BLUE}INFO: ingress=0 et httproute=0${NC}"
    fi

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📁 Namespace: $ns${NC} | $status_icon $status_text"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  🌐 Ingress    : ${BLUE}$ingress_count${NC}"
    echo -e "  🛣️  HTTPRoute : ${BLUE}$httproute_count${NC}"
    echo ""
done
