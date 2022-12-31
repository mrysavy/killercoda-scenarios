# Get all resources in namespace

## Intro
Při problémech s mazáním namespace je potřeba vědět, jak zobrazit všechn _resources_ v namespace. Každý asi zná příkaz `kubectl get all -n <namespace>`{{}}.
Ale ne každý ví, že ono `all`{{}} neznamená všechny `api-resource`{{}}, ale ve skutečnosti to znamená `api-resources`{{}} kategorie `all`{{}}.
A které to jsou lze získat následujícím příkazem:
```shell
kubectl api-resources --categories=all
```{{exec}}

Toto si můžeme ověřit např. touto dvojicí příkazů:
```shell
kubectl get all -n kube-public
kubectl get serviceaccounts -n kube-public
```{{exec}}
kdy první z příkazů (`get all`{{}}) nenajde žádný _resource_, ale druhý z příkazů (`get serviceaccounts`{{}}) najde `ServiceAccount`{{}} `default`{{}}.

Pokud chceme vypsat opravdu všechny _resources_ v daném namespace, lze použít např. následující příkaz:
```shell
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n kube-public
```{{exec}}
Tento příkaz vytvoří seznam všech _namespace-wide resource types_ jež podporují API call `list`{{}} a pro každý z nich vylistuje _resources_ v daném namespace.
