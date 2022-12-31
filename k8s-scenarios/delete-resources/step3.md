# Finalizer

## Intro
Důležitou roli v mazání _resources_ má **finalizer**.
Vzhledem k tomu, že některé _resources_ spravují **custom controllery**, tyto mohou na základě změn na `CustomResource`{{}} provádět nějaké operace mimo **Kuberentes** cluster.
Při vytvoření a modifikaci není problém, protože **custom controller** si může obhospodařovávat daný _resource_ a zapisovat si do něj libovolné stavové informace.
Problém však nastává při mazání, neboť pokud **API server** daný _resource_ smaže, už k němu nemá přístup ani **custom controller**.

Pro tyto případy je právě dostupná funkcionalita **finalizer**.

Každý _resource_ může mít v `metadata`{{}} pole `finalizers`{{}}, které obsahuje výčet jednotlivých finalizerů na _resource_ (`Namespace`{{}} má **finalizery** také ve `spec`{{}}, ale to je mimo scope tohoto LABu).
Pokud má nějaký _resource_ při mazání nastaven alespoň jeden **finalizer**, tento _resource_ zůstává v procesu mazání a tím i na **API serveru**.
To se vyznačuje nastavením fieldu `deletionTimestamp`{{}} v `metadata`{{}} _resource_ (v některých případech se nastavuje též `deletionGracePeriodSeconds`{{}}, ale to je mimo scope tohoto LABu).
Takový _resource_ je ve výpisech vidět ve stavu `Terminating`{{}}.

V tuto chvíli jednotlivé **custom controllery** detekují _resource_, který je v procesu mazání a zároveň má odpovídající **finalizer**.
Provedou všechny potřebné operace související se smazáním daného _resource_ a příslušný **finalizer** odeberou.

V momentě, kdy _resource_ nemá žádný **finalizer**, **Kubernetes API server** dokončí mazání _resource_.

Pokud **custom controller**, který spravuje daný **finalizer**, neběží, potom **finalizer** zůstává na _resource_ a ten nemůže být smazán.

**Finalizery** používají nejen **custom controllery**, ale také **Kubernetes** nativně. Nejznámější jsou:
- **finalizer** `kubernetes`{{}} na `Namespace`{{}} (ve `spec.finalizers`{{}}) - slouží k tomu, aby byly smazány všechny _resources_ uvnitř `Namespace`{{}} dříve, než bude smazán `Namespace`{{}}
- **finalizery** `kubernetes.io/pv-protection`{{}} / `kubernetes.io/pvc-protection`{{}} - slouží jako ochrana k tomu, aby nemohl být odstraněn `PersistentVolume`{{}} / `PersistentVolumeClaim`{{}}, pokud je používán 

Pozn.: pokud je _resource_ v procesu mazání, tak je možné jej dále modifikovat, avšak není možné přidat další **finalizer** (pouze odebrat).

## Demo
Pojďmě si vyzkoušet mazání resource s **finalizerem**.

Vytvořme `ConfigMap`{{}}:
```shell
kubectl create configmap test
```{{exec}}

Nyní nastavme **finalizer**:
```shell
kubectl patch configmap test -p '{"metadata": {"finalizers": ["csas.cz/finalizer"]}}'
```{{exec}}

A teď zkusme `ConfigMap`{{}} smazat:
```shell
kubectl delete configmap test --wait=false
```{{exec}}
a zkontrolujme, zda existuje:
```shell
kubectl get configmap test
```{{exec}}

Vidíme, že `ConfigMap`{{}} stále existuje. Tak se pojďme podívat na detail:
```shell
kubectl get configmap test -o yaml
```{{exec}}

Vidíme, že je `ConfigMap`{{}} v procesu mazání (má field `deletionTimestamp`{{}}) a že má **finalizer** `csas.cz/finalizer`{{}}.

Pokud **finalizer** odstraníme:
```shell
kubectl patch configmap test --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
```{{exec}}
a zkontrolujme, zda existuje:
```shell
kubectl get configmap test
```{{exec}}
vidíme, že `ConfigMap`{{}} je pryč:
