### Kubernetes namespace deleting
_Note: In Czech language only (for now, sorry)_

V tomto scénáři si ukážeme proč většinou není dobrý nápad mazat finalizer z namespace a co dělat v případě, že namespace nelze smazat
<br>
Vyzkoušíme si následující funkcionalitu:
- Vypsání všech resources v namespace
- Diagnostika proč nejde namespace smazat
- Mazání namespace při nefunkčním custom controlleru
- Mazání namespace při nefunkčním custom API serveru

Nezbytné základy lze získat v:
- LABu - TBD