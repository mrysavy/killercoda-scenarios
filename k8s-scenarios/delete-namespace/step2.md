# Namespace finalizers

## Intro
_Resource_ `Namespace`{{}} má `finalizers`{{}} nejen v `metadata`{{}}, ale také ve `spec`{{}}. A oboje se uplatňuje při mazání _resource_.
Avšak zatímco `metadata.finalizers`{{}} lze upravovat přímo editaci `Namespace`{{}}, `spec.finalizers`{{}} je upravitelné pouze přes subresource `/finalize`{{}}

Každý `Namespace`{{}} má ve `spec.finalizers`{{}} finalizer `kubernetes`{{}},
  díky kterému **Kubernetes** při mazání `Namespace`{{}} smaže všechny _resources_ které jsou jeho součástí
  (smaže jak _resources_ perzisované **Kubernetes API serverem**, tak i nechá smazat _resources_ perzistované **custom API serverem**).

Je důrazně nedoporučováno mazat **finalizer** `kubernetes`{{}}. Proto jej také nelze smazat přímou editací, ale pouze "speciálním" postupem.
Pokud tento **finalizer** smažeme z `Namespace`{{}} ve stavu `Terminating`{{}}, potom nemusí dojít ke smazání _resources_ vázaných k tomuto `Namespace`{{}} z **Kubernetes API serveru** nebo z **custom API serveru**.
Pokud tento **finalizer** smažeme z `Namespace`{{}} ve stavu `Active`{{}} (tzn. není v procesu mazání), potom smazání `Namespace`{{}} nemusí být dokončeno.

## Demo - smazání finalizeru
Pojďme si ukázat jak v případě potřeby odebrat **finalizer** `kubernetes`{{}} z `Namespace`{{}}.

Vytvoříme `Namespace`{{}}:
```shell
kubectl create namespace test
```{{exec}}
a zkontrolujeme **finalizer** `kubernetes`{{}} v `spec.finalizers`{{}}:
```shell
kubectl get namespace test -o yaml | yq eval 'del(.status)' -
```{{exec}}

Nejprve zkusíme odebrat finalizer tradičním postupem:
```shell
kubectl patch namespace test --type=json -p '[{"op": "remove", "path": "/spec/finalizers"}]'
```{{exec}}
ale tento postup nebyl úspěšný:
```shell
kubectl get namespace test -o yaml | yq eval 'del(.status)' -
```{{exec}}

Použijeme tedy subresource `/finalize`{{}} pomocí `kubectl replace --raw`{{}}:
```shell
NS=test; kubectl get ns test -o json | jq 'del(.spec.finalizers[] | select(. == "kubernetes"))' | kubectl replace -f- --raw /api/v1/namespaces/$NS/finalize
```{{exec}}
a následně potvrdíme úspěšnost:
```shell
kubectl get namespace test -o yaml | yq eval 'del(.status)' -
```{{exec}}

Pokud je potřeba, **finalizer** `kubernetes`{{}} vrátíme:
```shell
NS=test; kubectl get ns test -o json | jq '.spec.finalizers |= . + ["kubernetes"]' | kubectl replace -f- --raw /api/v1/namespaces/$NS/finalize
```{{exec}}
a následně potvrdíme úspěšnost:
```shell
kubectl get namespace test -o yaml | yq eval 'del(.status)' -
```{{exec}}

Nakonec `Namespace`{{}} smažme:
```shell
kubectl delete namespace test
```{{exec}}
