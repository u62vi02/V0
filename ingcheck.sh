#!/bin/bash
# ingcheck.sh
# Rapport du nombre d'Ingress et d'HTTPRoute par namespace (uat/develop)

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [-v] [-h]"
    echo "  -v  mode verbose (affiche les détails par namespace)"
    echo "  -h  affiche cette aide"
}

VERBOSE=0

while getopts ":vh" opt; do
    case "${opt}" in
        v)
            VERBOSE=1
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Option invalide: -${OPTARG}${NC}"
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

echo -e "${BLUE}🔍 Recherche des namespaces contenant 'uat' ou 'develop'...${NC}"
echo ""

# Récupérer les namespaces filtrés (triés)
namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -E '\-(development|uat|integration)$' | sort)

if [ -z "$namespaces" ]; then
    echo -e "${RED}Aucun namespace contenant 'uat' ou 'develop' trouvé${NC}"
    exit 0
fi

# Totaux globaux
total_ingress=0
total_httproute=0

for ns in $namespaces; do
    ingress_count=$(kubectl get ingress -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    httproute_count=$(kubectl get httproute -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    [ -z "$ingress_count" ] && ingress_count=0
    [ -z "$httproute_count" ] && httproute_count=0

    # Cumul global
    total_ingress=$((total_ingress + ingress_count))
    total_httproute=$((total_httproute + httproute_count))

    if [ "$ingress_count" -eq 0 ] && [ "$httproute_count" -gt 0 ]; then
        status_icon="✅"
        ns_color="$GREEN"
        status_text="${GREEN}OK: $httproute_count / $ingress_count ${NC}"
    elif [ "$ingress_count" -gt 0 ] && [ "$httproute_count" -gt 0 ]; then
        status_icon="⚠️"
        ns_color="$YELLOW"
        status_text="${YELLOW}ON GOING: $httproute_count / $ingress_count ${NC}"
    elif [ "$ingress_count" -gt 0 ] && [ "$httproute_count" -eq 0 ]; then
        status_icon="❌"
        ns_color="$RED"
        status_text="${RED}TO BEGIN: $httproute_count / $ingress_count ${NC}"
    else
        status_icon="ℹ️"
        ns_color="$BLUE"
        status_text="${BLUE}INFO: pas d'ingress ni httproute detecté ${NC}"
    fi

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "📁 Namespace: ${ns_color}$ns${NC} | $status_icon $status_text"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Bloc détaillé seulement en mode verbose
    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "  🌐 Ingress    : ${BLUE}$ingress_count${NC}"
        echo -e "  🛣️  HTTPRoute : ${BLUE}$httproute_count${NC}"
        echo ""
    fi
done

# Résumé global
echo -e "==================== SUMMARY ====================${NC}"
echo -e "Total Ingress détectés    : ${GREEN}$total_ingress${NC}"
echo -e "Total HTTPRoute détectées : ${GREEN}$total_httproute${NC}"
echo -e "=================================================${NC}"
