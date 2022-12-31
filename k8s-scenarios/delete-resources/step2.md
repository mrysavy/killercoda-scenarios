# Garbage Collector

## Intro
Funkcionalitu popsanou v předchozí kapitole má na starosti **Garbage Collector**, jež je nativní součástí Kubernetes (konkrétně **Controller Manageru**).
Úkolem Garbage Collectoru je mazat _resources_ jejichž **vlastník** neexistuje.

Vyzkoušejme co se stane, pokud nastavíme `ownerReferences`{{}} na neexistující resource:
- vytvoříme prázdnou `configMap`{{}}: `kubectl create configmap test-gc`{{exec}}
- ověříme jeho existenci: `kubectl get configmap test-gc`{{exec}}
- nastavíme `ownerReferences`{{}}:
```
kubectl patch configmap test-gc -p '{"metadata": {"ownerReferences": [{"apiVersion": "v1", "kind": "ConfigMap", "name": "noname", "uid": "00000", "blockOwnerDeletion": true}]}}'
```{{exec}}
- ověříme jeho existenci: `kubectl get configmap test-gc`{{exec}}
- a vidíme, že došlo ke smazání (na základě neexistujícího **vlastníka**)

Kubernetes _resource_ lze smazat ve třech různých režimech (`propagationPolicy`{{}}):
- kaskádově na popředí - `foreground`{{}}
- kaskádově na pozadí - `background`{{}} (default pro kubectl)
- nekaskádově - `orphan`{{}}
Rozdíl mezi mazáním na popředí a na pozadí je zejména v pořadí mazání **vlastníka** a **závislých** _resources_.
Při mazání na popředí (`foreground`{{}}) je **vlastník** smazán až po smazání všech **závislých** (řešeno pomocí finalizeru - viz. dále).
Při mazání na pozadí (`background`{{}}) je nejprve smzazán **vlastník** a díky **Garbage Collectoru** jsou následně smazány všechny **závislé** _resources_.

Nekaskádové mazání (`orphan`{{}}) znamená, že se ze všech **závislých** odebere vazba na **vlastníka** a poté je **vlastník** smazán. Původní **závislé** _resources_ tedy již jsou nezávislé a nebudou tedy smazány.

Kaskádové mazání na popředí má jedno specifikum. Součástí struktury pod `ownerReferences`{{}} je field `blockOwnerDeletion`{{}} (výchozí hodnota se nastavuje `true`{{}}), který určuje, zda daný **závislý** _resource_ skutečně blokuje smazání **vlastníka**.
Pokud je hodnota `false`{{}}, potom se mazání chová jako `background`{{}}, avšak pouze pro daný **závislý** _resource_. To znamená, že smazání **vlastníka** čaká pouze na smazání těch **závislých** _resources_, které mají nastaveno `blockOwnerDeletion: true`{{}}. Smazání **vlastníka** tak může být blokováno pouze některými z jeho **závislých** _resources_ a jinými nikoliv.

## Demo - foreground
Vytvoříme `ReplicaSet`{{}} (a počkáme na nastartování podů):
```
cat <<EOF | kubectl create -f-
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - image: nginx
          name: nginx
          imagePullPolicy: IfNotPresent
          lifecycle:
            preStop:
                exec:
                    command: ["/bin/sleep", "20"]
EOF
kubectl wait pods -l app=nginx --for condition=Ready --timeout=70s   # wait for rollout
```{{exec}}

A podívejme se na přehled vytvořených _resources_:
```
kubectl get replicaset,pod
```{{exec}}
Vidíme `ReplicaSet`{{}} i `Pod`{{}}, což je v pořádku.

Zkontrolujme `Pod`{{}} metadata:
```
kubectl get pod -l app=nginx -o yaml | yq eval '.items[0] | del(.spec,.status)' -
```{{exec}}
A vidíme, že je nastaveno `ownerReferences`{{}} na `ReplicaSet`{{}} a zároveň `blockOwnerDeletion: true`{{}}.

Nyní smažme `ReplicaSet`{{}} kaskádově na popředí:
```
kubectl delete replicaset nginx --cascade=foreground --wait=false
```{{exec}}
A podívejme se na přehled _resources_:
```
kubectl get replicaset,pod
```{{exec}}
Vidíme `ReplicaSet`{{}} (který nebude smazán dříve než `Pod`{{}}) i `Pod`{{}}, přičemž `Pod`{{}} je ve stavu `Terminating`{{}} (`Pod`{{}} má nastaveno, že mu zastavení trvá cca 20s (abychom měli čas pro kontrolu)).

Počkejme minutu a znovu se podívejme se na přehled _resources_:
```
kubectl get replicaset,pod
```{{exec}}
a vidíme, že se smazaly `ReplicaSet`{{}} i `Pod`{{}}:

## Demo - foreground - blockOwnerDeletion
Vytvoříme `ReplicaSet`{{}} (a počkáme na nastartování podů):
```
cat <<EOF | kubectl create -f-
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - image: nginx
          name: nginx
          imagePullPolicy: IfNotPresent
          lifecycle:
            preStop:
                exec:
                    command: ["/bin/sleep", "20"]
EOF
kubectl wait pods -l app=nginx --for condition=Ready --timeout=70s   # wait for rollout
```{{exec}}

A podívejme se na přehled vytvořených _resources_:
```
kubectl get replicaset,pod
```{{exec}}
Vidíme `ReplicaSet`{{}} i `Pod`{{}}, což je v pořádku.

Zkontrolujme `Pod`{{}} metadata:
```
kubectl get pod -l app=nginx -o yaml | yq eval '.items[0] | del(.spec,.status)' -
```{{exec}}
A vidíme, že je nastaveno `ownerReferences`{{}} na `ReplicaSet`{{}} a zároveň `blockOwnerDeletion: true`{{}}.

Nastavme `blockOwnerDeletion: true`{{}} na `Pod`{{}}:
```
kubectl patch pod $(kubectl get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}') --type=json -p '[{"op": "replace", "path": "/metadata/ownerReferences/0/blockOwnerDeletion", "value": false}]'
```{{exec}}

Nyní smažme `ReplicaSet`{{}} kaskádově na popředí:
```
kubectl delete replicaset nginx --cascade=foreground --wait=false
```{{exec}}
A podívejme se na přehled _resources_:
```
kubectl get replicaset,pod[oclogin-project.iml](..%2F..%2F..%2FCSAS%2FAzureOCP-old%2Foclogin-project%2Foclogin-project.iml)
```{{exec}}
Vidíme, že `ReplicaSet`{{}} byl smazán a zůstal jen `Pod`{{}}, který je ve stavu `Terminating`{{}} (má nastaveno, že mu zastavení trvá cca 20s (abychom měli čas pro kontrolu)).
Sice jsme použili `--cascade=foreground`{{}}, ale `Pod`{{}} má nastaveno `blockOwnerDeletion: false`{{}} a tudíž neblokuje smazání `ReplicaSet`{{}}.

Počkejme minutu a znovu se podívejme se na přehled _resources_:
```
kubectl get replicaset,pod
```{{exec}}
a vidíme, že se smazaly už i `Pod`{{}}:

## Demo - background
Vytvoříme `ReplicaSet`{{}} (a počkáme na nastartování podů):
```
cat <<EOF | kubectl create -f-
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - image: nginx
          name: nginx
          imagePullPolicy: IfNotPresent
          lifecycle:
            preStop:
                exec:
                    command: ["/bin/sleep", "20"]
EOF
kubectl wait pods -l app=nginx --for condition=Ready --timeout=70s   # wait for rollout
```{{exec}}

A podívejme se na přehled vytvořených _resources_:
```
kubectl get replicaset,pod
```{{exec}}
Vidíme `ReplicaSet`{{}} i `Pod`{{}}, což je v pořádku.

Nyní smažme `ReplicaSet`{{}} kaskádově na pozadí (v tomto případě je uvedení `--cascade=background`{{}} nadbytečné, neboť se jedná o výchozí hodnotu):
```
kubectl delete replicaset nginx --cascade=background --wait=false
```{{exec}}
A podívejme se na přehled _resources_:
```
kubectl get replicaset,pod
```{{exec}}
Vidíme, že `ReplicaSet`{{}} byl smazán a zůstal jen `Pod`{{}}, který je ve stavu `Terminating`{{}} (má nastaveno, že mu zastavení trvá cca 20s (abychom měli čas pro kontrolu)).

Počkejme minutu a znovu se podívejme se na přehled _resources_:
```
kubectl get replicaset,pod
```{{exec}}
a vidíme, že se smazal už i `Pod`{{}}:

## Demo - orphan
Vytvoříme `ReplicaSet`{{}} (a počkáme na nastartování podů):
```
cat <<EOF | kubectl create -f-
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - image: nginx
          name: nginx
          imagePullPolicy: IfNotPresent
          lifecycle:
            preStop:
                exec:
                    command: ["/bin/sleep", "20"]
EOF
kubectl wait pods -l app=nginx --for condition=Ready --timeout=70s   # wait for rollout
```{{exec}}

A podívejme se na přehled vytvořených _resources_:
```
kubectl get replicaset,pod
```{{exec}}
Vidíme `ReplicaSet`{{}} i `Pod`{{}}, což je v pořádku.

Zkontrolujme `Pod`{{}} metadata:
```
kubectl get pod -l app=nginx -o yaml | yq eval '.items[0] | del(.spec,.status)' -
```{{exec}}
A vidíme, že je nastaveno `ownerReferences`{{}} na `ReplicaSet`{{}}.

Nyní smažme `ReplicaSet`{{}} nekaskádově:
```
kubectl delete replicaset nginx --cascade=orphan --wait=false
```{{exec}}
A podívejme se na přehled _resources_:
```
kubectl get replicaset,pod
```{{exec}}
Vidíme `ReplicaSet`{{}} byl smazán a zůstal jen `Pod`{{}}, který ovšem není ve stavu `Terminated`{{}}.

A když zkontrolujeme metadata:
```
kubectl get pod -l app=nginx -o yaml | yq eval '.items[0] | del(.spec,.status)' -
```{{exec}}
tak vidíme, že `ownerReferences`{{}} již není.
