# cka-helm-practice

Examen práctico de **Helm para el CKA**: 13 preguntas con enunciado tipo examen,
que se resuelven **haciendo cosas sobre un cluster real**, y un corrector que
comprueba el estado de verdad del cluster y te da una nota sobre 100.

Aprobado en 66, igual que el CKA.

No hay preguntas de teoría ni de opción múltiple: o la release queda como pide
el enunciado, o no puntúa.

---

## Uso en Killercoda (lo habitual)

Abre **[killercoda.com/playgrounds/scenario/cka](https://killercoda.com/playgrounds/scenario/cka)**
— es el playground cuya versión de Kubernetes coincide con la del examen — y pega:

```bash
curl -sL https://raw.githubusercontent.com/alvarodiez20/cka-helm-practice/main/bootstrap.sh | bash
```

O clonando:

```bash
git clone https://github.com/alvarodiez20/cka-helm-practice.git
cd cka-helm-practice && ./setup.sh
```

`setup.sh` instala Helm si falta, monta un **repositorio local de charts servido
en 127.0.0.1:8879** (así el examen funciona aunque no haya internet), y siembra
el cluster con dos releases en el estado que necesitan las preguntas.

Al terminar, `setup.sh` deja los comandos del examen listos. Cárgalos en el
shell actual (en los siguientes ya entran solos, vía `~/.bashrc`):

```bash
source ~/cka-helm-practice/activate.sh
```

Y a partir de ahí, **desde cualquier directorio**:

```bash
exam           # las 13 preguntas con sus puntos
q 4            # leer una pregunta
grade          # corregir todo -> nota sobre 100
grade 4        # corregir solo una
solve 4        # solución (solo cuando te rindas)
examreset      # volver a sembrar el entorno desde cero
```

`q`, `grade` y `solve` autocompletan el número de pregunta con Tab. Son
funciones de shell, no un REPL: sigues teniendo `kubectl` y `helm` a mano, que
es donde se resuelve el examen de verdad.

Si prefieres no tocar tu shell, todo funciona igual llamando al script:
`./exam.sh`, `./exam.sh q 4`, `./exam.sh grade`, `./exam.sh reset`.

La sesión de Killercoda caduca en ~1 hora. Al volver, `./setup.sh` otra vez.

---

## Las 13 preguntas

| # | Pts | Qué se practica |
|---|---|---|
| 1 | 7 | `install` con `--create-namespace`, `--version` y `--set` |
| 2 | 8 | Diagnosticar con `history` y arreglar con `rollback` |
| 3 | 6 | Encontrar una release perdida: `helm list -A` |
| 4 | 7 | `upgrade` con `--reuse-values` sin perder configuración |
| 5 | 8 | `helm template` (renderizar sin tocar el cluster) |
| 6 | 7 | `get values -a` (values efectivos, defaults incluidos) |
| 7 | 7 | `uninstall --keep-history` |
| 8 | 8 | Resucitar una release desde su historial |
| 9 | 10 | `helm create` + editar `Chart.yaml` (`version` vs `appVersion`) + `lint` |
| 10 | 7 | `helm package` con `-d` |
| 11 | 8 | Instalar desde un `.tgz` local con `--wait` |
| 12 | 9 | `--set-string` frente a `--set` (tipos en los values) |
| 13 | 8 | Dependencias: `Chart.yaml` + `helm dependency update` |

Las preguntas están encadenadas a propósito, como en el examen real: la 4 modifica
lo que hiciste en la 1, y la 8 deshace la 7. El corrector lo tiene en cuenta y
comprueba el historial, no solo el estado actual, así que resolver una pregunta
posterior **no te tumba** la nota de una anterior.

---

## Qué monta `setup.sh`

- Chart `demo-app` empaquetado en tres versiones (0.1.0, 0.2.0, 0.3.0) con
  `appVersion` distinta en cada una, servido como repo local `ckarepo`.
- Namespace `apps` con la release **`legacy`**: tres revisiones, y la actual
  apuntando a una imagen inexistente. Material para la pregunta 2.
- Un namespace de nombre poco obvio con la release **`ghost`**, para la 3.
- Directorio `~/answers/` donde vuelcas las respuestas en fichero.

Todo lo que crea vive en `~/cka-helm`, `~/answers`, `~/mychart` y `~/dist`.

---

## Requisitos

Un nodo Linux con `kubectl` apuntando a un cluster, `python3` y `curl`.
Helm lo instala el propio `setup.sh` si no está. Probado pensando en Killercoda,
pero funciona igual en kind, minikube o cualquier cluster de usar y tirar.

> No lo ejecutes contra un cluster que te importe: `setup.sh` borra y recrea los
> namespaces `apps`, `hidden-77`, `web` y `dev`.
