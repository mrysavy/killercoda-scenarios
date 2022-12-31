# API Services
## Setup
Pro potřeby tohoto LABu je potřeba malá příprava:
```shell
# metrics-server installation
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# patch for working in this lab correctly
kubectl patch -n kube-system deployment metrics-server --type=json -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
# wait for rolling out
kubectl rollout -n kube-system status deployment metrics-server --watch

# setup etcdctl environment
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
```{{exec}}

## Intro
Standardně na Kubernetes clusteru jsou všechny _resources_ uloženy v `etcd`{{}} a to včetně `CustomResource`{{}}.
Kubernetes však podporuje také tzv. `APIService`{{}}, kdy dané _resources_ nespravuje ani neeviduje přímo **Kubernetes**, ale **custom API server**.

Na rozdíl od `CustomResource`{{}}, kde sice logiku vykonává custom **controller** ale perzistenci _resource_ v `etcd`{{}} má na starosti **Kubernetes apiserver**, v případě `APIService` **Kuberentes** nedělá ani persistenci a jen patřičné API volání přesměrovává na **custom API server**.
Díky tomu daný _resource_ může být perzistovaný jakýmkoliv způsobem, případně perzistovaný vůbec být nemusí a jeho manifest může vznikat **on-demand**.

Která API jsou spravována **custom API serverem** zjistíme vypsáním `APIService`{{}}:
```
kubectl get apiservices
```{{exec}}
Ty které mají ve sloupci `SERVICE`{{}} hodnotu `Local`{{}}, ty jsou spravováný přímo **Kubernetes API serverem** a ty ostatní jsou spravovány **custom API serverem**, který reprezentuje `Service`{{}} zobrazená v tomto sloupci.
Zde vidíme, že `v1beta1.metrics.k8s.io`{{}} je sprovaváno přes `Service`{{}} `kube-system/metrics-server`{{}}. Nejedná se však přímo o _resource_, ale o Version a APIGroup.
Přehled spravovaných resources nám zobrazí následující příkaz (v parametru `--api-group`{{}} je pouze APIGroup a nikoliv Version:
```shell
kubectl api-resources --api-group metrics.k8s.io
```{{exec}}
Zde vidíme, že tento **custom API server** spravuje resources `NodeMetrics`{{}} a `PodMetrics`{{}}.

Můžeme si ověřit, že ačkoliv `nodemetrics`{{}} existují v clusteru:
```shell
kubectl get nodemetrics
```{{exec}}
nenacházejí se v etcd:
```shell
etcdctl get --keys-only --prefix / | grep nodemetrics
```{{exec}}

A jak toto souvisí s problematikou mazání Kubernetes _resources_?
Tyto _resources_ jsou sice spravovány **custom API serverem**, ale přístup k nim je standardně přes **Kubernetes API** a je tedy možné je spravovat například pomocí `kubectl`{{}}.
Je zde však jedna podstatná poznámka - tyto _resource_ nemusí nutně podporovat všechny operace a např. zde:
```shell
kubectl api-resources --api-group metrics.k8s.io -o wide
```{{exec}}
vidíme, že tyto _resources_ `delete`{{}} nepodporují (viz. sloupec `VERBS`{{}}) narozdíl třeba od většiny základních _resources_:
```shell
kubectl api-resources --api-group '' -o wide
```{{exec}}

A proto příkaz:
```shell
kubectl delete nodemetrics controlplane
```{{exec}}
končí s chybou: `Error from server (MethodNotAllowed): the server does not allow this method on the requested resource`{{}}.

Pokud **custom API server**, který obhospodařuje dané API, neběží, nelze s odpovídajícími _resources_ vůbec pracovat a některé komponenty clusteru mohou hlásit chyby, případně nedokončovat některé operace.
Nejlepší způsob řešení situace je vždy oprava funkčnosti **custom API serveru**. Pokud to není možné, lze **custom API server** odregistrovat z **Kubernetes**, čímž bude **Kubernetes API server** opět plně funkční.
Je však nutné pamatovat na to, že _resources_ spravované tímto **custom API serverem**, které mohou být perzistovány v okolních systémech, nebudou dále spravovány a tudíž může dojít k narušení integrity.
Je nutno pamatovat také na to, že daná `API`{{}} nebudou cluster dále nebude znát, což může rozbít funkcionalitu jiných **custom controllerů**, jinak funkčních.

Konkrétně v případě nedostupného nebo neexistujícího `metrics.k8s.io`{{}} API group sice z povahu funkcionality nebude narušena žádná datová integrita
  (dané _resources_ `PodMetrics`{{}} a `NodeMetrics`{{}} nejsou perzistovány v žádném systému, jedná se o pohled nad metrikami jednotlivých nodů/podů; _resources_ ani nepodporují `create`{{}} nebo `delete`{{}}),
  ale přestane fungovat např. automatické škálování podů - `HorizontalPodAutoscaler`{{}}.

Pokud nějaký **custom API server** neběží, není např. možné smazat namespace (zůstává ve stavu `Terminating`{{}}).

## Demo - nedostupný **custom API server**
Zastavme `metrics-server`{{}}:
```shell
kubectl scale deployment metrics-server -n kube-system --replicas=0
```{{exec}}
a vidíme, že daný **custom API server** není dostupný:
```shell
kubectl get apiservices v1beta1.metrics.k8s.io
```{{exec}}
a vidíme, že **Kubernetes** dané API nezná a dává najevo, že seznam API není kompletní:
```shell
kubectl api-resources --api-group metrics.k8s.io -o wide
```{{exec}}
chybovou hláškou: `error: unable to retrieve the complete list of server APIs: metrics.k8s.io/v1beta1: the server is currently unable to handle the request`{{}}.

Pokud API server opět spustíme:
```shell
kubectl scale deployment metrics-server -n kube-system --replicas=1
kubectl rollout -n kube-system status deployment metrics-server --watch
```{{exec}}
tak výše uvedené příkazy již opět pracují korektně:
```shell
kubectl get apiservices v1beta1.metrics.k8s.io
kubectl api-resources --api-group metrics.k8s.io -o wide
```{{exec}}

## Demo - odregistrování `APIService`{{}}
Zastavme `metrics-server`{{}}:
```shell
kubectl scale deployment metrics-server -n kube-system --replicas=0
```{{exec}}
a zkontrolujme očekávanou chybu (`error: unable to retrieve the complete list of server APIs: metrics.k8s.io/v1beta1: the server is currently unable to handle the request`{{}}):
```shell
kubectl get apiservices v1beta1.metrics.k8s.io
kubectl api-resources --api-group metrics.k8s.io -o wide
```{{exec}}

Nyní odeberme registraci APIService:
```shell
kubectl delete apiservices v1beta1.metrics.k8s.io
```{{exec}}
a zkontrolujme stav:
```shell
kubectl get apiservices v1beta1.metrics.k8s.io
kubectl api-resources --api-group metrics.k8s.io -o wide
```{{exec}}
Odpovídající `api-resource`{{}} již v seznamu nevidíme,
  ale zároveň **Kubernetes API server** nehlásí nedostupnost **custom API serveru**,
  pouze nám sděluje, že daná `APIService`{{}} neexistuje (`Error from server (NotFound): apiservices.apiregistration.k8s.io "v1beta1.metrics.k8s.io" not found`).)
A `metrics-server` nám stále neběží, viz.:
```shell
kubectl get pod -l k8s-app=metrics-server -n kube-system
```{{exec}}

## Cleanup
Na závěr LABu uklidíme:
```shell
kubectl delete --ignore-not-found -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```{{exec}}
