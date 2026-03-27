#!/bin/bash
# check_java_with_summary.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Compteurs
TOTAL_OK=0
TOTAL_KO=0
TOTAL_UNKNOWN=0
declare -a KO_PROCESSES

# Fonction pour extraire et comparer les versions Java
# Retourne 0 si OK, 1 si KO, 2 si inconnu
check_java_version() {
    local version_string=$1
    
    # Extraire le numéro de version
    local version_num=""
    local is_java8=false
    
    # Vérifier si c'est Java 8 (1.8.x)
    if [[ "$version_string" == *"1.8"* ]] || [[ "$version_string" == *"1.8."* ]]; then
        is_java8=true
        # Extraire le numéro de update pour Java 8 (ex: 1.8.0_392 -> 392)
        if [[ "$version_string" =~ 1\.8\.0_([0-9]+) ]]; then
            local update_num="${BASH_REMATCH[1]}"
            version_num="$update_num"
            # Seuil pour Java 8: u372
            if [ "$update_num" -ge 372 ]; then
                return 0  # OK
            else
                return 1  # KO (version trop ancienne)
            fi
        else
            # Si on ne trouve pas le numéro de update, considérer comme inconnu
            return 2
        fi
    fi
    
    # Pour Java 11 et plus
    if [[ "$version_string" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        
        # Seuil pour Java 11: 11.0.16
        if [ "$major" -gt 11 ]; then
            return 0  # Java 17, 21, etc. sont OK
        elif [ "$major" -eq 11 ]; then
            if [ "$minor" -gt 0 ]; then
                return 0
            elif [ "$minor" -eq 0 ] && [ "$patch" -ge 16 ]; then
                return 0
            else
                return 1
            fi
        else
            return 1  # Version inférieure à 11
        fi
    fi
    
    # Si on ne peut pas extraire la version
    return 2
}

# Fonction pour obtenir la version Java depuis un PID
get_java_version() {
    local ns=$1
    local pod=$2
    local container=$3
    local pid=$4
    
    # Méthode 1: via /proc/pid/exe
    local java_path=$(kubectl exec -n $ns $pod -c $container -- readlink -f /proc/$pid/exe 2>/dev/null)
    if [ ! -z "$java_path" ]; then
        local version=$(kubectl exec -n $ns $pod -c $container -- $java_path -version 2>&1 | head -n1)
        echo "$version"
        return 0
    fi
    
    # Méthode 2: via les arguments du processus
    local cmdline=$(kubectl exec -n $ns $pod -c $container -- cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
    local java_bin=$(echo "$cmdline" | awk '{print $1}')
    if [[ "$java_bin" == *"java"* ]]; then
        local version=$(kubectl exec -n $ns $pod -c $container -- $java_bin -version 2>&1 | head -n1)
        echo "$version"
        return 0
    fi
    
    # Méthode 3: chercher dans l'environnement du processus
    local java_home=$(kubectl exec -n $ns $pod -c $container -- cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep JAVA_HOME | cut -d= -f2)
    if [ ! -z "$java_home" ]; then
        local version=$(kubectl exec -n $ns $pod -c $container -- $java_home/bin/java -version 2>&1 | head -n1)
        echo "$version"
        return 0
    fi
    
    echo "unknown"
    return 1
}

# Fonction pour obtenir une description lisible de la version
get_version_description() {
    local version_string=$1
    
    if [[ "$version_string" == *"1.8"* ]]; then
        if [[ "$version_string" =~ 1\.8\.0_([0-9]+) ]]; then
            local update="${BASH_REMATCH[1]}"
            echo "Java 8 (update $update)"
        else
            echo "Java 8 (update inconnu)"
        fi
    elif [[ "$version_string" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        echo "Java $major.$minor.$patch"
    else
        echo "Version inconnue"
    fi
}

echo -e "${BLUE}🔍 Vérification des versions Java${NC}"
echo -e "${BLUE}📊 Seuils requis:${NC}"
echo -e "   • Java 8: ${YELLOW}≥ 1.8.0_372 (update 372)${NC}"
echo -e "   • Java 11: ${YELLOW}≥ 11.0.16${NC}"
echo -e "   • Java 17+: ${GREEN}Toutes versions acceptées${NC}"
echo ""

# Récupérer les namespaces filtrés
namespaces=$(kubectl get ns -o name | cut -d/ -f2 | grep -E 'uat|develop')

if [ -z "$namespaces" ]; then
    echo -e "${RED}Aucun namespace contenant 'uat' ou 'develop' trouvé${NC}"
    exit 0
fi

for ns in $namespaces; do
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📁 Namespace: $ns${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Récupérer tous les pods
    for pod in $(kubectl get pods -n $ns -o name | cut -d/ -f2); do
        # Vérifier le statut du pod
        pod_status=$(kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}')
        if [ "$pod_status" != "Running" ]; then
            continue
        fi
        
        # Récupérer les conteneurs
        containers=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[*].name}')
        
        for container in $containers; do
            echo -e "  ${BLUE}📦 $pod/$container${NC}"
            
            # Trouver les processus Java avec ps
            java_processes=$(kubectl exec -n $ns $pod -c $container -- ps aux 2>/dev/null | grep -E '[j]ava|[j]re' || true)
            
            if [ -z "$java_processes" ]; then
                echo -e "    ${YELLOW}⚠️  Aucun processus Java détecté${NC}"
                continue
            fi
            
            # Analyser chaque processus Java
            echo "$java_processes" | while IFS= read -r process; do
                pid=$(echo "$process" | awk '{print $2}')
                cmd=$(echo "$process" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
                
                # Obtenir la version Java
                version=$(get_java_version "$ns" "$pod" "$container" "$pid")
                
                if [ "$version" != "unknown" ] && [ ! -z "$version" ]; then
                    check_java_version "$version"
                    result=$?
                    version_desc=$(get_version_description "$version")
                    
                    if [ $result -eq 0 ]; then
                        echo -e "    ✅ ${GREEN}PID $pid: $version_desc${NC}"
                        echo -e "       ${GREEN}Version: $version${NC}"
                        ((TOTAL_OK++))
                    elif [ $result -eq 1 ]; then
                        # Afficher le détail du seuil manqué
                        if [[ "$version" == *"1.8"* ]]; then
                            if [[ "$version" =~ 1\.8\.0_([0-9]+) ]]; then
                                local update="${BASH_REMATCH[1]}"
                                echo -e "    ❌ ${RED}PID $pid: $version_desc (update $update < 372)${NC}"
                            else
                                echo -e "    ❌ ${RED}PID $pid: $version_desc (version < 1.8.0_372)${NC}"
                            fi
                        else
                            echo -e "    ❌ ${RED}PID $pid: $version_desc (version < 11.0.16)${NC}"
                        fi
                        echo -e "       ${RED}Version: $version${NC}"
                        ((TOTAL_KO++))
                        KO_PROCESSES+=("$ns/$pod/$container (PID $pid): $version ($version_desc)")
                    else
                        echo -e "    ⚠️  ${YELLOW}PID $pid: Version non détectable${NC}"
                        echo -e "       ${YELLOW}Version string: $version${NC}"
                        ((TOTAL_UNKNOWN++))
                    fi
                    echo -e "       Commande: ${cmd:0:80}..."
                else
                    echo -e "    ⚠️  ${YELLOW}PID $pid: Version non détectable${NC}"
                    ((TOTAL_UNKNOWN++))
                fi
                echo ""
            done
        done
    done
    echo ""
done

# Afficher le résumé
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📊 RÉSUMÉ DES VÉRIFICATIONS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "✅ Processus OK: ${GREEN}$TOTAL_OK${NC}"
echo -e "❌ Processus KO: ${RED}$TOTAL_KO${NC}"
echo -e "⚠️  Processus non détectables: ${YELLOW}$TOTAL_UNKNOWN${NC}"
echo -e "📊 Total processus Java: $((TOTAL_OK + TOTAL_KO + TOTAL_UNKNOWN))"

if [ $TOTAL_KO -gt 0 ]; then
    echo ""
    echo -e "${RED}⚠️  PROCESSUS AVEC VERSION NON CONFORME:${NC}"
    echo -e "${RED}   (Java 8 < 1.8.0_372 ou Java 11 < 11.0.16)${NC}"
    echo ""
    for process in "${KO_PROCESSES[@]}"; do
        echo -e "  ${RED}❌ $process${NC}"
    done
    echo ""
    echo -e "${RED}🔴 NON CONFORME - Des processus Java ne respectent pas les seuils requis${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ TOUS LES PROCESSUS SONT CONFORMES${NC}"
    echo -e "${GREEN}   - Java 8: ≥ 1.8.0_372${NC}"
    echo -e "${GREEN}   - Java 11: ≥ 11.0.16${NC}"
    echo -e "${GREEN}   - Java 17+: OK${NC}"
    exit 0
fi
