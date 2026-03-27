#!/bin/bash
# check_java_versions_improved.sh

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Recherche des processus Java dans les namespaces contenant 'uat' ou 'develop'...${NC}"
echo ""

# Récupérer les namespaces filtrés
namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -E 'uat|develop')

if [ -z "$namespaces" ]; then
    echo -e "${RED}Aucun namespace contenant 'uat' ou 'develop' trouvé${NC}"
    exit 0
fi

for ns in $namespaces; do
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📁 Namespace: $ns${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Récupérer tous les pods
    pods=$(kubectl get pods -n $ns -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$pods" ]; then
        echo "  Aucun pod trouvé"
        echo ""
        continue
    fi
    
    for pod in $pods; do
        # Vérifier le statut du pod
        status=$(kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}')
        ready=$(kubectl get pod $pod -n $ns -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        
        if [ "$status" != "Running" ] || [ "$ready" != "True" ]; then
            echo -e "  ⚠️  ${YELLOW}$pod: $status (prêt: $ready) - Pod non prêt${NC}"
            continue
        fi
        
        # Récupérer les conteneurs
        containers=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[*].name}')
        
        for container in $containers; do
            echo -e "  ${BLUE}└─ Conteneur: $container${NC}"
            
            # Test 1: Vérifier si Java est dans le PATH
            if kubectl exec -n $ns $pod -c $container -- which java > /dev/null 2>&1; then
                # Test 2: Vérifier s'il y a un processus Java en cours
                java_process=$(kubectl exec -n $ns $pod -c $container -- ps aux 2>/dev/null | grep -v grep | grep java | head -n1)
                
                if [ ! -z "$java_process" ]; then
                    # Un processus Java est en cours d'exécution
                    version=$(kubectl exec -n $ns $pod -c $container -- java -version 2>&1 | head -n1)
                    echo -e "    ✅ ${GREEN}Processus Java actif${NC}"
                    echo -e "       Version: $version"
                    echo -e "       Process: $(echo $java_process | awk '{print $11, $12, $13, $14}' | cut -c1-80)"
                else
                    # Java est installé mais aucun processus en cours
                    version=$(kubectl exec -n $ns $pod -c $container -- java -version 2>&1 | head -n1)
                    echo -e "    ⚠️  ${YELLOW}Java installé mais aucun processus en cours${NC}"
                    echo -e "       Version: $version"
                fi
            else
                # Test alternatif: chercher directement les processus Java
                java_process=$(kubectl exec -n $ns $pod -c $container -- ps aux 2>/dev/null | grep -v grep | grep -E 'java|jre' | head -n1)
                if [ ! -z "$java_process" ]; then
                    echo -e "    ✅ ${GREEN}Processus Java détecté (java non dans PATH)${NC}"
                    echo -e "       Process: $(echo $java_process | awk '{print $11, $12, $13, $14}' | cut -c1-80)"
                    # Essayer d'obtenir la version via le chemin complet
                    java_path=$(echo $java_process | awk '{print $11}')
                    if [ ! -z "$java_path" ]; then
                        version=$(kubectl exec -n $ns $pod -c $container -- $java_path -version 2>&1 | head -n1 2>/dev/null)
                        if [ ! -z "$version" ]; then
                            echo -e "       Version: $version"
                        fi
                    fi
                else
                    # Vérifier si le conteneur tourne sur Java (via env vars)
                    java_home=$(kubectl exec -n $ns $pod -c $container -- env 2>/dev/null | grep JAVA_HOME)
                    if [ ! -z "$java_home" ]; then
                        echo -e "    ℹ️  ${BLUE}JAVA_HOME détecté mais commande java non accessible${NC}"
                        echo -e "       $java_home"
                    else
                        echo -e "    ❌ ${RED}Aucun processus Java détecté${NC}"
                    fi
                fi
            fi
            echo ""
        done
    done
    echo ""
done
