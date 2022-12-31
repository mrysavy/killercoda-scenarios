# Finalizer
## Intro
Důležitou roli v mazání _resources_ má `finalizer`{{}}.
Vzhledem k tomu, že některé _resources_ spravují **custom controllery**, tyto mohou na základě změn na `CustomResource`{{}} provádět nějaké operace mimo **Kuberentes** cluster.
Při vytvoření a modifikaci není problém, protože **custom controller** si může obhospodařovávat daný _resource_ a zapisovat si do něj libovolné stavové informace.
Problém však nastává při mazání, neboť pokud **API server** daný _resource_ smaže, už k němu nemá přístup ani **custom controller**.

Pro tyto případy je právě dostupná funkcionalita `finalizer`{{}}.

Každý _resource_ může mít v `metadata`{{}} pole `finalizers`{{}}, které obsahuje výčet jednotlivých finalizerů na _resource_.
Pokud má nějaký _resource_ při mazání nastaven alespoň jeden finalizer, **Kubernetes API server** pouze tento _resource_ označí ke smazání, ale vlastní smazání neproběhne.
Toto označení spočívá v nastavením mj. fieldu `deletionTimestamp`{{}} do přidá do `metadata`{{}} resource.
Takový _resource_ je ve výpisech vidět ve stavu `Terminating`{{}}.

V tuto chvíli jednotlivé **custom controllery** detekují _resource_, který je označen ke smazání a zároveň má odpovídající `finalizer`{{}}.
Provedou všechny potřebné operace související se smazáním daného _resource_ a příslušný `finalizer`{{}} odeberou.

V momentě, kdy _resource_ nemá žádný `finalizer`{{}}, **Kubernetes API server** dokončí mazání _resource_.

Pokud **custom controller**, který spravuje daný finalizer neběží

Pozn.: pokud je _resource_ označen ke smazání, tak je možné jej dále modifikovat, avšak není možné přidat další `finalizer`{{}} (pouze odebrat).

## Demo
Pojďmě si vyzkoušet mazání resource

TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
TBD<br/>
