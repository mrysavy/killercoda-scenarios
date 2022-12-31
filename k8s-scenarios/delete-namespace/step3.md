# Diagnostic of impossibility to delete namespace

## Intro
Může se stát, že smažete `Namespace`{{}}, ale ten zůstává ve stavu `Terminating`{{}}.
Některé návody v diskuzích na Internetu radí smazat **finalizer** `kubernetes`{{}} z `Namespace`{{}}.
To by měla ale být až poslední možnost. Vždy je třeba nejprve udělat diagnostiku a odebrání **finalizeru** `kubernetes`{{}} z `Namespace`{{}} nechat až jako poslední možnost.

Nemožnost smazat namespace je v drtivé většině případů způsobena jedním z následujících scénářů, které si dále popíšeme a ukážeme možnosti řešení:
- namespace obsahuje _resources_ mající **finalizer** který spravuje **custom controller**, jež ale nepracuje správně (případně je spravován ručně)
- v clusteru je `APIService`{{}} jehož **custom API server** ale nepracuje správně
- namespace obsahuje `Pod`{{}}, který je schedulován na nedostupném `Node`{{}}

Ještě může nastat situace, kdy `Namespace`{{}} nelze smazat z důvodu nedostatečných oprávnění nebo zamítnutí **policy enginem**.
V takovém případě `Namespace`{{}} je ve stavu `Active`{{}} a není v procesu mazání (nemá field `deletionTimestamp`).
Jedná se o standardní stav a řešením je zajistit si patřičná oprávnění, případně úpravu RBAC nebo politiky.

Dalši situací je samozřejmě stav, kdy namespace má kromě **finalizeru** `kubernetes`{{}} ještě i jiný finalizer,
  který spravuje **custom controller**, jež ale nepracuje správně.
A není rozhodující, zda je tento **finalizer** v bloku `spec`{{}} nebo `metadata`{{}}.
V tomto případě je řešení stejné jako když je daný **finalizer** na _resource_ uvnitř namespace (viz. Demo - finalizer).

## Setup
Pro potřeby tohoto LABu je potřeba malá příprava:
```shell
# metrics-server installation
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# patch for working in this lab correctly
kubectl patch -n kube-system deployment metrics-server --type=json -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
# wait for rolling out
kubectl rollout -n kube-system status deployment metrics-server --watch
# allow schedule on master node
kubectl taint nodes controlplane node-role.kubernetes.io/control-plane:NoSchedule-
```{{exec}}

## Demo - finalizer
Ukažme si diagnostiku a nápravu situace, kdy **custom controller** obsluhující **finalizer** nepracuje správně nebo je **finalizer spravován ručně**
  (na _resource_ uvnitř mazaného `Namespace`{{}}).

Vytvořme `Namespace`{{}} `test`{{}} příkazem:
```shell
kubectl create namespace test
```{{exec}}
Následně vytvoříme pro příklad `ConfigMap`{{}}:
```shell
kubectl create configmap test -n test --from-literal=test="Ukazkovy test"
```{{exec}}
a nastavme mu **finalizer**, abychom nasimulovali nemožnost smazání `Namespace`{{}}:
```shell
kubectl patch configmap test -n test -p '{"metadata": {"finalizers": ["csas.cz/finalizer"]}}'
```{{exec}}

Nyní smažme `Namespace`{{}}:
```shell
kubectl delete namespace test --wait=false
```{{exec}}
a zkontrolujme stav:
```shell
kubectl get namespace test
kubectl get namespace test -o yaml | yq eval 'del(.spec,.status)' -
```{{exec}}
`Namespace`{{}} je ve stavu `Terminating`{{}} a je v procesu mazání (field `deletionTimestamp`{{}}).

Pojďme se podívat, jak můžeme tento stav diagnostikovat. Podívejme se na `status`{{}} `Namespace`{{}}:
```shell
kubectl get namespace test -o yaml | yq eval '.status' -
```{{exec}}
kde vidíme (zaměřme se na položky, kde `status == "True"`{{}}):
```yaml{18-21,23-26}
conditions:
  - lastTransitionTime: "2023-01-22T22:33:35Z"
    message: All resources successfully discovered
    reason: ResourcesDiscovered
    status: "False"
    type: NamespaceDeletionDiscoveryFailure
  - lastTransitionTime: "2023-01-22T22:33:35Z"
    message: All legacy kube types successfully parsed
    reason: ParsedGroupVersions
    status: "False"
    type: NamespaceDeletionGroupVersionParsingFailure
  - lastTransitionTime: "2023-01-22T22:33:35Z"
    message: All content successfully deleted, may be waiting on finalization
    reason: ContentDeleted
    status: "False"
    type: NamespaceDeletionContentFailure
  - lastTransitionTime: "2023-01-22T22:33:35Z"
    message: 'Some resources are remaining: configmaps. has 1 resource instances'
    reason: SomeResourcesRemain
    status: "True"
    type: NamespaceContentRemaining
  - lastTransitionTime: "2023-01-22T22:33:35Z"
    message: 'Some content in the namespace has finalizers remaining: csas.cz/finalizer in 1 resource instances'
    reason: SomeFinalizersRemain
    status: "True"
    type: NamespaceFinalizersRemaining
phase: Terminating
```{{}}
Zvýrazněné řádky ukazují, že namespace obsahuje 1 `ConfigMap`{{}} / obsahuje 1 _resource_ mající **finalizer** `csas.cz/finalizer`{{}}.

Správným řešením v tomto případě je zjistit, proč nepracuje **controller**, který spravuje **finalizer** `csas.cz/finalizer`{{}}.
V případě že není možné **controller** obnovit a máme jistotu, že tento **finalizer** můžeme bez dopadu smazat z `ConfigMap`{{}}, je to možné řešení.
V tomto případě tomu tak je, neboť se jedná o ručně spravovaný **finalizer** bez externí vazby.
Pojďme tedy odebrat **finalizer** (po ověření, že se jedná o jediný **finalizer**, můžeme jednodušeji odebrat všechny **finalizery**):
```shell
kubectl patch configmap test -n test --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
```{{exec}}

A po krátké chvíli můžeme vidět, že `Namespace`{{}} byl smazán:
```shell
kubectl get namespace test
```{{exec}}

## Demo - apiservice
Ukažme si diagnostiku a nápravu situace, kdy **custom API server** obsluhující `APIService`{{}} nepracuje správně.

Vytvořme `Namespace`{{}} `test`{{}} příkazem:
```shell
kubectl create namespace test
```{{exec}}
Následně zastavíme `metrics-server`{{}}, abychom nasimulovali nemožnost smazání `Namespace`{{}}:
```shell
kubectl scale deployment metrics-server -n kube-system --replicas=0
```{{exec}}

Nyní smažme `Namespace`{{}}:
```shell
kubectl delete namespace test --wait=false
```{{exec}}
a zkontrolujme stav:
```shell
kubectl get namespace test
kubectl get namespace test -o yaml | yq eval 'del(.spec,.status)' -
```{{exec}}
`Namespace`{{}} je ve stavu `Terminating`{{}} a je v procesu mazání (field `deletionTimestamp`{{}}).

Pojďme se podívat, jak můžeme tento stav diagnostikovat. Podívejme se na `status`{{}} `Namespace`{{}}:
```shell
kubectl get namespace test -o yaml | yq eval '.status' -
```{{exec}}
kde vidíme (zaměřme se na položky, kde `status == "True"`{{}}):
```yaml{3-6}
conditions:
  - lastTransitionTime: "2023-01-22T23:34:29Z"
    message: 'Discovery failed for some groups, 1 failing: unable to retrieve the complete list of server APIs: metrics.k8s.io/v1beta1: the server is currently unable to handle the request'
    reason: DiscoveryFailed
    status: "True"
    type: NamespaceDeletionDiscoveryFailure
  - lastTransitionTime: "2023-01-22T23:34:29Z"
    message: All legacy kube types successfully parsed
    reason: ParsedGroupVersions
    status: "False"
    type: NamespaceDeletionGroupVersionParsingFailure
  - lastTransitionTime: "2023-01-22T23:34:29Z"
    message: All content successfully deleted, may be waiting on finalization
    reason: ContentDeleted
    status: "False"
    type: NamespaceDeletionContentFailure
  - lastTransitionTime: "2023-01-22T23:34:29Z"
    message: All content successfully removed
    reason: ContentRemoved
    status: "False"
    type: NamespaceContentRemaining
  - lastTransitionTime: "2023-01-22T23:34:29Z"
    message: All content-preserving finalizers finished
    reason: ContentHasNoFinalizers
    status: "False"
    type: NamespaceFinalizersRemaining
phase: Terminating
```{{}}
Zvýrazněné řádky ukazují, že není možné zajistit všechny _resources_ v namespace, konkrétně z jedné API group - `metrics.k8s.io/v1beta1`{{}},
  a to z důvodu: `the server is currently unable to handle the request`{{}}.

Správným řešením v tomto případě je zjistit, proč nepracuje **custom API server**, který spravuje `metrics.k8s.io/v1beta1`{{}}.
Pojďme tedy "opravit" `metrics-server`{{}}:
```shell
kubectl scale deployment metrics-server -n kube-system --replicas=1
kubectl rollout -n kube-system status deployment metrics-server --watch
```{{exec}}

A po krátké chvíli můžeme vidět, že `Namespace`{{}} byl smazán:
```shell
kubectl get namespace test
```{{exec}}

Dokončení smazání `Namespace`{{}} lze zajistit i workaroundem, který lze (při znalosti konsekvencí) aplikovat.
Jedná so o:
- `APIService`{{}} delete: `kubectl delete apiservice v1beta1.metrics.k8s.io`{{copy}}
Praktická ukázka tohoto workaroundu je mimo scope tohoto workshopu, ale pomocí vhodně použitých výše uvedených příkazů je možno vyzkoušet v prostředí tohoto workshopu.

Na závěr uvedu, že odregistrování `APIService`{{}} vnímám jako měnší riziko než odebrání `kubernetes`{{}} **finalizeru** z `Namespace`{{}}.
To, že _resources_ spravovaná **custom API serverem** nebudou smazány (pokud je perzistuje, což nemusí být pravidlo), totiž nastane v obou případech.

## Demo - unavailable `Node`{{}}
Ukažme si diagnostiku a nápravu situace, kdy neběží `Node`{{}}, na které je naschedulován `Pod`{{}} z mazaného `Namespace`{{}}.

Vytvořme `Namespace`{{}} `test`{{}} příkazem:
```shell
kubectl create namespace test
```{{exec}}
Následně vytvoříme `Deployment`{{}} `nginx`{{}} se dvěma replikami (každá poběží na jiném `Node`{{}}, pokud jsme správně odebrali **taint** z `Node`{{}}, viz. Setup):
```shell
kubectl create deployment nginx -n test --image nginx --replicas=2
kubectl rollout status deployment nginx -n test --watch
```{{exec}}

Dále zastavme `Node`{{}} `node01`{{}}:
```shell
ssh node01 systemctl mask kubelet --now
kubectl wait nodes --for=condition=Ready=Unknown node01 --timeout=120s
```{{exec}}

Nyní smažme `Namespace`{{}}:
```shell
kubectl delete namespace test --wait=false
```{{exec}}
a zkontrolujme stav:
```shell
kubectl get namespace test
kubectl get namespace test -o yaml | yq eval 'del(.spec,.status)' -
```{{exec}}
`Namespace`{{}} je ve stavu `Terminating`{{}} a je v procesu mazání (field `deletionTimestamp`{{}}).

Pojďme se podívat, jak můžeme tento stav diagnostikovat. Podívejme se na `status`{{}} `Namespace`{{}}:
```shell
kubectl get namespace test -o yaml | yq eval '.status' -
```{{exec}}
kde vidíme (zaměřme se na položky, kde `status == "True"`{{}}):
```yaml{8-11}
conditions:
  - lastTransitionTime: "2023-01-24T21:40:07Z"
    message: All resources successfully discovered
    reason: ResourcesDiscovered
    status: "False"
    type: NamespaceDeletionDiscoveryFailure
  - lastTransitionTime: "2023-01-24T21:40:07Z"
    message: All legacy kube types successfully parsed
    reason: ParsedGroupVersions
    status: "False"
    type: NamespaceDeletionGroupVersionParsingFailure
  - lastTransitionTime: "2023-01-24T21:40:07Z"
    message: All content successfully deleted, may be waiting on finalization
    reason: ContentDeleted
    status: "False"
    type: NamespaceDeletionContentFailure
  - lastTransitionTime: "2023-01-24T21:40:07Z"
    message: 'Some resources are remaining: pods. has 1 resource instances'
    reason: SomeResourcesRemain
    status: "True"
    type: NamespaceContentRemaining
  - lastTransitionTime: "2023-01-24T21:40:07Z"
    message: All content-preserving finalizers finished
    reason: ContentHasNoFinalizers
    status: "False"
    type: NamespaceFinalizersRemaining
phase: Terminating
```{{}}
Zvýrazněné řádky ukazují, že namespace obsahuje 1 `Pod`{{}}.

Proveďme diagnostiku podu:
```yaml
kubectl get pod -n test -o yaml | yq eval '.items[0].status.conditions' -
```{{exec}}
kde vidíme (zaměřme se na položku, kde `type == "DisruptionTarget"`{{}}):
```yaml{19-22}
- lastProbeTime: null
  lastTransitionTime: "2023-01-24T21:38:58Z"
  status: "True"
  type: Initialized
- lastProbeTime: null
  lastTransitionTime: "2023-01-24T21:39:48Z"
  status: "False"
  type: Ready
- lastProbeTime: null
  lastTransitionTime: "2023-01-24T21:39:00Z"
  status: "True"
  type: ContainersReady
- lastProbeTime: null
  lastTransitionTime: "2023-01-24T21:38:58Z"
  status: "True"
  type: PodScheduled
- lastProbeTime: null
  lastTransitionTime: "2023-01-24T21:44:54Z"
  message: 'Taint manager: deleting due to NoExecute taint'
  reason: DeletionByTaintManager
  status: "True"
  type: DisruptionTarget
```{{}}
Zvýrazněné řádky ukazují, že `Pod`{{}} byl smazán pro splnění `NoExecute taint`{{}}, což může (ale nemusí) značit nedostupnost `Node`{{}}.
To však dokážeme snadno ověřit. Výpisem (ve sloupci `NODE`{{}}):
```yaml
kubectl get pod -n test -o wide
```{{exec}}
zjistíme dotčený `Node`{{}} a výpisem (sloupec `STATUS`{{}}:
```yaml
kubectl get node
```{{exec}}
ověříme, že je `Node`{{}} nedostupný.

Nedostupný `Node`{{}} je důvod, proč němůže být smazán `Pod`{{}}, protože cluster neví, zda byly odpovídající **containery** ukončeny.

Správným řešením v tomto případě je zajistit opětovnou funkčnost `Node`{{}} (diagnostika neběžejícího `Node`{{}} není ve scope tohoto workshopu).

Pojďme tedy "opravit" `Node`{{}}:
```shell
ssh node01 systemctl unmask kubelet --now; ssh node01 systemctl start kubelet
kubectl wait nodes --for=condition=Ready node01 --timeout=120s
```{{exec}}

A po krátké chvíli můžeme vidět, že `Namespace`{{}} byl smazán:
```shell
kubectl wait namespace --for=delete test --timeout=120s
kubectl get namespace test
```{{exec}}

Dokončení smazání `Namespace`{{}} lze zajistit i dvěma workaroundy, které lze (při znalosti konsekvencí) aplikovat.
Jedná so o:
- force `Pod`{{}} delete: `kubectl delete pod -l app=nginx -n test --force`{{copy}}
- `Node`{{}} delete: `kubectl delete node node01`{{copy}}
Praktické ukázky těchto workaroundů jsou mimo scope tohoto workshopu, ale pomocí vhodně použitých výše uvedených příkazů je možno vyzkoušet v prostředí tohoto workshopu.

## Demo - namespace finalizer removal
Pokud není jiná možnost (a víme, co děláme), je možné `kubernetes`{{}} **finalizer** z `Namespace`{{}} odebrat.
Pojďme si ale ukázat, co se stane, pokud **finalizer** odebereme v situacích popsaných výše ("Demo - finalizer" a "Demo - apiservice fix" a "Demo - apiservice unregister").

Vytvořme `Namespace`{{}} `test`{{}} příkazem:
```shell
kubectl create namespace test
```{{exec}}

Následně vytvoříme pro příklad `ConfigMap`{{}}:
```shell
kubectl create configmap test -n test --from-literal=test="Ukazkovy test"
```{{exec}}
a nastavme mu **finalizer**, abychom nasimulovali nemožnost smazání `Namespace`{{}}:
```shell
kubectl patch configmap test -n test -p '{"metadata": {"finalizers": ["csas.cz/finalizer"]}}'
```{{exec}}

Následně zastavíme `metrics-server`{{}}, abychom nasimulovali nemožnost smazání `Namespace`{{}}:
```shell
kubectl scale deployment metrics-server -n kube-system --replicas=0
```{{exec}}

Nyní smažme `Namespace`{{}}:
```shell
kubectl delete namespace test --wait=false
```{{exec}}
a zkontrolujme stav:
```shell
kubectl get namespace test
kubectl get namespace test -o yaml | yq eval 'del(.spec,.status)' -
```{{exec}}
`Namespace`{{}} je ve stavu `Terminating`{{}} a je v procesu mazání (field `deletionTimestamp`{{}}).

Pojďme se podívat, jak můžeme tento stav diagnostikovat. Podívejme se na `status`{{}} `Namespace`{{}}:
```shell
kubectl get namespace test -o yaml | yq eval '.status' -
```{{exec}}
kde vidíme (zaměřme se na položky, kde `status == "True"`{{}}):
```yaml{3-6,18-21,23-26}
conditions:
  - lastTransitionTime: "2023-01-23T11:39:27Z"
    message: 'Discovery failed for some groups, 1 failing: unable to retrieve the complete list of server APIs: metrics.k8s.io/v1beta1: the server is currently unable to handle the request'
    reason: DiscoveryFailed
    status: "True"
    type: NamespaceDeletionDiscoveryFailure
  - lastTransitionTime: "2023-01-23T11:39:27Z"
    message: All legacy kube types successfully parsed
    reason: ParsedGroupVersions
    status: "False"
    type: NamespaceDeletionGroupVersionParsingFailure
  - lastTransitionTime: "2023-01-23T11:39:27Z"
    message: All content successfully deleted, may be waiting on finalization
    reason: ContentDeleted
    status: "False"
    type: NamespaceDeletionContentFailure
  - lastTransitionTime: "2023-01-23T11:39:27Z"
    message: 'Some resources are remaining: configmaps. has 1 resource instances'
    reason: SomeResourcesRemain
    status: "True"
    type: NamespaceContentRemaining
  - lastTransitionTime: "2023-01-23T11:39:27Z"
    message: 'Some content in the namespace has finalizers remaining: csas.cz/finalizer in 1 resource instances'
    reason: SomeFinalizersRemain
    status: "True"
    type: NamespaceFinalizersRemaining
phase: Terminating
```{{}}
Zvýrazněné řádky ukazují, že namespace obsahuje 1 `ConfigMap`{{}} / obsahuje 1 _resource_ mající **finalizer** `csas.cz/finalizer`{{}} a dále
  že není možné zajistit všechny _resources_ v namespace, konkrétně z jedné API group - `metrics.k8s.io/v1beta1`{{}} (důvod: `the server is currently unable to handle the request`{{}}).

Než odeberu **finalizer** `kubernetes`{{}} z `Namespace`{{}}, tak si zkontroluji, které všechny _resources_ mi zůstanou v `etcd`{{}}:
```shell
kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | xargs -n 1 kubectl get --show-kind --ignore-not-found -n test 2>/dev/null
```{{exec}}
Normálně bychom řešili nejprve tyto _resources_ než bychom přistiupili k odebrání **finalizeru**, ale v tomto případě tam máme `ConfigMap`{{}} `test`{{}} úmyslně pro demostrační účely.

Nyní odeberme **finalizer** `kubernetes`{{}}:
```shell
NS=test; kubectl get ns test -o json | jq 'del(.spec.finalizers[] | select(. == "kubernetes"))' | kubectl replace -f- --raw /api/v1/namespaces/$NS/finalize
```{{exec}}
a ujistíme se, že je `Namespace` smazán:
```shell
kubectl get namespace test
```{{exec}}

Nyní vytvořme nový `Namespace`{{}} se stejným jménem:
```shell
kubectl create namespace test
```{{exec}}
a ujistíme se, že je `Namespace` vytvořen:
```shell
kubectl get namespace test
```{{exec}}

A pojďme se podívat, co se stalo:
- nový `Namespace`{{}} obsahuje původní `ConfigMap`{{}} (viz. `kubectl get namespace/test configmap/test -n test`{{exec}} - sloupec `AGE`{{}}), která je ovšem stále v procesu mazání (`kubectl get configmap test -n test -o yaml`{{exec}})
- `kubectl`{{}} (např. `kubectl api-resources > /dev/null`{{exec}}) nám stále vrací chyby: `couldn't get resource list for metrics.k8s.io/v1beta1: the server is currently unable to handle the request`{{}}
- `Namespace`{{}} opět nejde smazat, a to ze stejných důvodů (`kubectl delete namespace test --wait=false`{{exec}}; `kubectl get namespace test -o yaml | yq eval '.status' -`{{exec}})
Je to z toho důvodu, že jsme neodstranili příčinu nemožnosti smazat `Namespace`{{}}. Pokud to uděláme nyní, tj:
```shell
kubectl patch configmap test -n test --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
kubectl scale deployment metrics-server -n kube-system --replicas=1
kubectl rollout -n kube-system status deployment metrics-server --watch
```{{exec}}
tak po chvilce zjistíme, že se `Namespace`{{}} korektně smazal (`kubectl get namespace test`{{exec}}) a další vytvoření/smazání `Namespace`{{}} se stejným jménem je již v pořádku:
```shell
kubectl create namespace test
kubectl get namespace test
kubectl delete namespace test
kubectl get namespace test
```{{exec}}
