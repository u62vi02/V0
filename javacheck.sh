#!/bin/bash
# check_java_versions_filtered.sh

echo "Checking Java versions in namespaces containing 'uat' or 'develop'..."

# Récupérer les namespaces filtrés
namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -E 'uat|develop')

if [ -z "$namespaces" ]; then
    echo "Aucun namespace contenant 'uat' ou 'develop' trouvé"
    exit 0
fi

for ns in $namespaces; do
    echo "========================================="
    echo "Namespace: $ns"
    echo "========================================="
    
    # Récupérer tous les pods dans le namespace
    for pod in $(kubectl get pods -n $ns -o jsonpath='{.items[*].metadata.name}'); do
        # Vérifier le statut du pod
        status=$(kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}')
        if [ "$status" != "Running" ]; then
            echo "  ⚠️  $pod: $status (non exécuté)"
            continue
        fi
        
        # Vérifier les conteneurs du pod
        containers=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[*].name}')
        for container in $containers; do
            echo -n "  📦 $pod/$container: "
            # Tenter d'obtenir la version Java
            java_version=$(kubectl exec -n $ns $pod -c $container -- java -version 2>&1 | head -n1)
            if [ $? -eq 0 ] && [ -n "$java_version" ]; then
                echo "$java_version"
            else
                echo "❌ Java non trouvé"
            fi
        done
    done
    echo ""
done
