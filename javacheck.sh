#!/bin/bash

# Loop through all namespaces
for namespace in $(kubectl get ns --no-headers | awk '{print $1}'); do
  # Loop through all pods in each namespace
  for pod in $(kubectl get pods -n $namespace --no-headers | awk '{print $1}'); do
    # Get the container name (assuming there is only one container per pod)
    container=$(kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[0].name}')

    # Check if Java is running in the container
    if kubectl exec -n $namespace $pod -- ps aux | grep java; then
      echo "Java is running in container $container of pod $pod in namespace $namespace."
      # Test Java version
      kubectl exec -n $namespace $pod -- java -version
    else
      echo "Java is not running in container $container of pod $pod in namespace $namespace. Please check if Java is installed and running."
    fi
  done
}