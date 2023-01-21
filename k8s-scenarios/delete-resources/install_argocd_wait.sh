#!/bin/bash

echo -n "Installing ArgoCD..."
while [ ! -f /tmp/finished ]; do
    echo -n '.'
    sleep 1;
done;
echo " done"

echo -n "Waiting for Argo CD..."
argocd_check=""

while [[ $argocd_check != True ]]; do
    argocd_check=$(kubectl get pods -l app.kubernetes.io/name=argocd-server -o 'jsonpath={ ..status.conditions[?(@.type=="Ready")].status }' -n argocd)
    echo -n '.'
    sleep 1;
done;
echo " done"

echo "ArgoCD admin password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o go-template="{{ .data.password | base64decode }}"; echo)"
