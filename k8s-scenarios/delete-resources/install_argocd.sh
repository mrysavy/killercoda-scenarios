#!/bin/bash

kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --namespace argocd --version 5.16.13

touch /tmp/finished
