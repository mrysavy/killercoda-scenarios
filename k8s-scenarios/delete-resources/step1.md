# Owner Reference
## Intro
`ownerReferences`{{}} je pole v metadatech libovolného Kubernetes _resource_, které umožňuje vazby mezi _resources_ typu **vlastník - závislý**.
Tato vazba se velmi často uplatňuje u _resources_, které jsou vytvářeny automaticky na základě jiného _resource_
  a zajišťuje, že při smazání **vlastníka** budou automaticky smazané i **závislé** _resources_.<br/>
`ownerReferences`{{}} je vždy uvedeno na `závislém` _resource_ a odkazuje na **vlastníka**. Vlastníků může být i více, ale to není obvyklé a v takovém případě se smaže **závislý** resource až v případě smazání posledního **vlastníka** (při mazání předchozích **vlastníků** se jen odebere odpovídající `ownerReferences`{{}} z metadat **závislého** resource).

**Vlastník** _namespace-level_ _resource_ může být jen _resource_ ze stejného namespace nebo _cluster-level_ _resource_.<br/>
**Vlastník** _cluster-level_ _resource_ může být jen _cluster-level_ _resource_.<br/>
Pokud je jako **vlastník** nastaven neexistující _resource_, potom je **závislý** _resource_ smazán.

Často bývá pravidlem, že pokud smažu **závislý** _resource_, tak jej nějaký **controller** (přímo k8s nebo 3rd party) založí znovu, přičemž často bývá dopad minimální.<br/>
Například pokud smažu `Pod`{{}} a běží mi více replik a jsou splněny další předpoklady na úrovni aplikace, může být takováto operace úplně bez dopadu na provoz aplikace. Následně Kubernetes vytvoří `Pod`{{}} nový.<br/>
Právě tímto způsobem se v prostředí Kubernetes často řeší troiubleshooting nebo i restart aplikace.

### Sample
`ownerReferences`{{}} má následující podobu:
```yaml{6-12}
apiVersion: v1
kind: Pod
metadata:
  name: nginx-1234567890-abcde
  namespace: default
  ownerReferences:
    - apiVersion: apps/v1
      blockOwnerDeletion: true
      controller: true
      kind: ReplicaSet
      name: nginx-1234567890
      uid: 3e8b8184-aef2-4a43-90bf-b288e29383e4
```
Vazba vždy musí obsahovat nejen typ _resource_ (`apiVersion`{{}} a `kind`{{}}) a jméno (`name`{{}}), ale také `uid`{{}}.

### Demo
Typickým příkladem je `Deployment`{{}}, na jehož základě vzniká `ReplicaSet`{{}} a na jeho základě `Pod`{{}}. Nebo `CronJob`{{}} - `Job`{{}} - `Pod`{{}}.

Pojďme si jeden takový vytvořit (a počkat na nastartování):
```
kubectl create deployment nginx --image nginx
kubectl rollout status deployment nginx --watch
```{{exec}}

A podívejme se na přehled vytvořených _resources_:
```
kubectl get deployment,replicaset,pod
```{{exec}}
Vidíme, že se vytvořil `Deployment`{{}}, `ReplicaSet`{{}} i `Pod`{{}} a můžeme zkontrolovat metadata.

Nejprve zkontrolujeme `Deployment`{{}}:
```
kubectl get deployment nginx -o yaml | yq eval '. | del(.spec,.status)' -
```{{exec}}
a zjistíme, že neobsahuje `ownerReference`{{}}, což je v pořádku.

Nyní se podívejme na `ReplicaSet`{{}}:
```
kubectl get replicaset -l app=nginx -o yaml | yq eval '.items[0] | del(.spec,.status)' -
```{{exec}}
a vidíme, že **vlastníkem** je _resource_ `Deployment`{{}} s názvem `nginx`{{}}, protože tento `ReplicaSet`{{}} vznikl právě na základě uvedeného `Deployment`{{}}:

Nakonec zkontrolujeme ještě `Pod`{{}}:
```
kubectl get pod -l app=nginx -o yaml | yq eval '.items[0] | del(.spec,.status)' -
```{{exec}}
a vidíme, že **vlastníkem** je výše zmíněný `ReplicaSet`{{}}.

Teď smažeme `Deployment`{{}}:
```
kubectl delete deployment nginx --wait
```{{exec}}
a vidíme, že se smazaly i `ReplicaSet`{{}} a `Pod`{{}}:
```
kubectl get deployment,replicaset,pod
```{{exec}}
