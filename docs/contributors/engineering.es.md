# Bash de producción con ShellSpec

Guía de diseño para herramientas escritas en Bash puro (>= 4.4) con ShellSpec
como framework de tests. Cada fragmento de esta página está **verificado
ejecutándolo** — no escrito de memoria. Donde la versión mínima de Bash importa,
se dice.

Esta página va de cómo está construido el código. Lo que la herramienta acabada
**no** hace —los fallos silenciosos, los comandos destructivos, las dependencias
que no declara— está en [Limitaciones](../users/limitations.md).

!!! warning "Este repositorio promete Bash 4.0, no 4.4"
    La guía asume 4.4+. Este proyecto declara **4+** en su README, así que
    `${var@Q}` (4.4), `local -n` (4.3) y `BASH_ARGV0` (5.0) no se pueden usar en
    `src/scripts/` sin un respaldo. Hay un test que lo vigila
    (`src/tests/bundle_spec.sh`). Si subes el requisito, ese test es donde queda
    anotado.

---

## 1. Blindar el entorno y el modo estricto

### El boilerplate

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
```

| Flag | Qué hace | Por qué |
|---|---|---|
| `-e` | aborta al primer comando que falla | un error silencioso a mitad de un script destructivo es peor que abortar |
| `-u` | una variable sin definir es un error | `rm -rf "$DIR/"` con `DIR` vacía se lleva la raíz |
| `-o pipefail` | una tubería falla si falla cualquier tramo | sin esto, `comando_que_falla \| tee log` devuelve 0 |
| **`-E`** | **el trap ERR lo heredan funciones y subshells** | **sin esto tu manejador de errores no salta justo donde importa** |
| `IFS=$'\n\t'` | quita el espacio del separador | evita partir palabras por accidente en rutas con espacios |

!!! warning "Este repositorio NO ejecuta ese boilerplate, y es a propósito"
    Aquí todos los scripts ejecutables arrancan con `set -uo pipefail` y nada
    más: ocho de los nueve ficheros de `src/scripts/`, más `build.sh` y
    `deps.sh`. `common.sh` no fija nada, porque es la biblioteca que cargan los
    demás. `set -e` está **prohibido** por
    [Cómo contribuir](../contributing.md): `pick()`, `confirm()` y `grep`
    devuelven != 0 como respuesta legítima, y abortar al primer distinto de cero
    sería abortar porque el usuario dice que no a un menú. Tampoco hay
    `IFS=$'\n\t'` en ningún sitio, ni un solo `trap ERR`: en todo el producto
    hay dos traps, una limpieza `EXIT` en `dashboard.sh` y otra `RETURN` en
    `deps.sh`.

    El precio se paga, no se esquiva. Sin `-e`, `build.sh` avisa por stderr de
    que le falta una entrada, **sale con `0`** y escribe el fichero único igual:
    quita `src/commands.txt` y el bundle se construye llevando dentro
    `DCC_HELP_SRC=''`, o sea ninguna ayuda. Verificado. Lee el §1 como la regla
    general y este aviso como la excepción permanente.

`-E` (`errtrace`) es el que casi todo el mundo se deja. **Verificado:**

```console
$ bash -c 'set -euo pipefail; trap "echo TRAP" ERR; f(){ false; }; f'
(nada)                     # sin -E el trap NO entra en la función

$ bash -c 'set -Eeuo pipefail; trap "echo TRAP" ERR; f(){ false; }; f'
TRAP
```

### Traza global con `trap ERR`

```bash
_traceback() {
	local rc=$1 cmd=$2 line=$3 i
	printf '\n[ERROR] rc=%s en la línea %s: %s\n' "$rc" "$line" "$cmd" >&2
	printf 'Pila (lo más reciente primero):\n' >&2
	for ((i = 1; i < ${#FUNCNAME[@]} - 1; i++)); do
		printf '  %s() en %s:%s\n' \
			"${FUNCNAME[i]}" "${BASH_SOURCE[i+1]##*/}" "${BASH_LINENO[i]}" >&2
	done
}
trap '_traceback "$?" "$BASH_COMMAND" "$LINENO"' ERR
```

Salida real:

```
[ERROR] rc=1 en la línea 16: false
Pila (lo más reciente primero):
  level_3() en tb.sh:17
  level_2() en tb.sh:18
  level_1() en tb.sh:19
```

Los tres arrays mágicos, y el desplazamiento que hay que respetar:

- `FUNCNAME[i]` — el nombre de la función en el nivel `i`
- `BASH_LINENO[i]` — la línea **desde la que** se llamó a `FUNCNAME[i]`
- `BASH_SOURCE[i+1]` — el fichero que contiene esa llamada. **`i+1`, no `i`**:
  `BASH_SOURCE[i]` es donde la función está *definida*, no desde donde se la
  *llama*.

Los argumentos se pasan **posicionalmente** (`"$?" "$BASH_COMMAND" "$LINENO"`).
Leerlos dentro de `_traceback` daría los valores del propio manejador.

### Limpieza con `trap EXIT`

`EXIT` salta siempre: salida limpia, aborto por `set -e` o `exit` explícito.
**Verificado** — el `false` aborta y la limpieza corre igual:

```console
$ bash -c 'set -Eeuo pipefail; tmp=$(mktemp -d); trap "rm -rf $tmp; echo LIMPIADO" EXIT; false'
LIMPIADO
```

Declara el trap **inmediatamente** después de crear el recurso:

```bash
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT     # aquí, no tres líneas más abajo
```

Para varios recursos, acumula en un array. Un segundo `trap … EXIT`
**sustituye** al primero, no se apila:

```bash
declare -a _CLEANUP=()
_cleanup() { local p; for p in "${_CLEANUP[@]:-}"; do rm -rf "$p"; done; }
trap _cleanup EXIT

tmp=$(mktemp -d);   _CLEANUP+=("$tmp")
otro=$(mktemp -d);  _CLEANUP+=("$otro")
```

### Los tres agujeros de `set -e`

`set -e` **no** es una red de seguridad completa. Se apaga solo en tres sitios:

```bash
# 1. En una condición: el fallo es el dato, no un error
if procesar; then ... fi          # -e NO aplica dentro de procesar
procesar && echo ok               # aquí tampoco

# 2. `local` se traga el código de salida
local x=$(false)                  # el rc de `local` es 0. El fallo desaparece.
local x; x=$(false)               # correcto: el rc del comando

# 3. Solo cuenta el último tramo de una tubería, salvo con pipefail
false | true                      # rc=0 sin pipefail
```

El número 2 es el que más daño hace, porque es idéntico a simple vista a la
forma correcta.

---

## 2. Tipado defensivo

Bash no tiene tipos. Lo que sí tiene son **atributos de variable**, y usarlos es
la diferencia entre un script y una herramienta.

### Atributos de `declare`

```bash
declare -i contador=0        # entero: contador+=1 suma, no concatena
declare -a lista=()          # array indexado
declare -A mapa=()           # array asociativo (diccionario)
declare -r CONSTANTE="fija"  # solo lectura
declare -n ref=otra_var      # nameref (Bash 4.3+)
```

`declare -i` es el que más disgustos silenciosos ahorra:

```bash
declare -i n=5; n+=1     # -> 6
declare    s=5; s+=1     # -> "51"   <- el bug clásico
```

### Ámbito: `declare` dentro de una función es LOCAL

**Esta es la trampa número uno de Bash y falla en silencio.** Verificado:

```console
$ bash -c 'f(){ declare -r C=1; }; f; echo "fuera: C=${C:-<sin definir>}"'
fuera: C=<sin definir>
```

El caso peligroso es `-A`:

```bash
cargar() { declare -A MAPA; }   # MAPA muere al volver
cargar
MAPA[clave]="valor"             # MAPA ya no es asociativo: es INDEXADO
```

Y no revienta. Un array indexado evalúa `MAPA[clave]` como **aritmética**, saca
`0`, y **todas las claves escriben en la misma casilla**. El programa no casca —
devuelve el valor equivocado.

Reglas:

- El `declare -A/-a` global va **fuera** de toda función.
- Dentro de las funciones, siempre `local` — incluidos los contadores de bucle.
- ¿Necesitas una global desde dentro de una función? `declare -g` (Bash 4.2+).

### Funciones guarda con códigos de salida semánticos

Devuelve códigos distintos por clase de error. Un `1` para todo no le dice nada
a quien llama:

```bash
readonly E_OK=0 E_TYPE=64 E_RANGE=65 E_FORMAT=66 E_MISSING=67

# assert_is_int <valor> [nombre]
assert_is_int() {
	local v=${1-} name=${2:-valor}
	[[ -n $v ]]            || { printf '%s: vacío\n'          "$name" >&2; return "$E_MISSING"; }
	[[ $v =~ ^-?[0-9]+$ ]] || { printf '%s: no es entero: %q\n' "$name" "$v" >&2; return "$E_TYPE"; }
	return "$E_OK"
}

# assert_in_range <valor> <min> <max>
assert_in_range() {
	local v=$1 min=$2 max=$3
	assert_is_int "$v" || return
	(( v >= min && v <= max )) \
		|| { printf 'fuera de [%s,%s]: %s\n' "$min" "$max" "$v" >&2; return "$E_RANGE"; }
}

# assert_is_email <valor>
assert_is_email() {
	local v=${1-}
	[[ $v =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] \
		|| { printf 'email inválido: %q\n' "$v" >&2; return "$E_FORMAT"; }
}
```

Tres detalles que no son cosméticos:

- `${1-}` en vez de `${1:-}` distingue "no se ha pasado" de "se ha pasado vacío",
  y sobrevive a `set -u`.
- `[[ $v =~ … ]]` con el patrón **sin comillas**: entrecomillarlo lo convierte en
  literal.
- `%q` al imprimir el valor malo: un valor con saltos de línea o escapes no te
  destroza el log.

Para JSON no hay validación honesta sin `jq`. No la finjas:

```bash
assert_is_json() {
	command -v jq >/dev/null || { printf 'jq no está instalado\n' >&2; return "$E_MISSING"; }
	printf '%s' "${1-}" | jq -e . >/dev/null 2>&1 \
		|| { printf 'JSON inválido\n' >&2; return "$E_FORMAT"; }
}
```

### "Objetos" con namerefs

`local -n` (Bash 4.3+) pasa una variable **por referencia**. Es lo más parecido a
un struct que ofrece Bash. **Verificado:**

```bash
# new_server <nombre_de_variable> <host> <puerto>
new_server() {
	local -n _obj=$1
	_obj=([host]="$2" [port]="$3" [state]="stopped")
}

server_url() {
	local -n _obj=$1
	printf 'https://%s:%s' "${_obj[host]}" "${_obj[port]}"
}

declare -A web
new_server web example.com 8443
server_url web        # -> https://example.com:8443
```

!!! danger "La colisión de nombres del nameref"
    Si quien llama usa una variable con el **mismo nombre** que el nameref, Bash
    aborta con *"circular name reference"*. Prefija siempre los namerefs
    (`_obj`, `__ref`) y no uses ese prefijo fuera.

    ```bash
    f() { local -n obj=$1; ...; }
    declare -A obj; f obj      # <- revienta
    ```

Alternativa sin namerefs, compatible con Bash 4.0: un único diccionario global
con claves compuestas.

```bash
declare -A OBJECTS
OBJECTS[web.host]="example.com"
OBJECTS[web.port]="8443"
```

---

## 3. Modularidad y espacios de nombres

### Resolver la ruta absoluta

Un `source` relativo depende del directorio desde el que te hayan invocado.
Resuelve siempre contra el **fichero**, nunca contra el cwd:

```bash
_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/log.sh
. "$_DIR/lib/log.sh"
```

- `cd --` y `dirname --` protegen de rutas que empiezan por `-`.
- `pwd -P` resuelve los enlaces simbólicos: dos rutas al mismo fichero dejan de
  ser dos rutas.
- El comentario `# shellcheck source=…` es **obligatorio**, o shellcheck no puede
  seguir el módulo y `-x` deja de servir para nada.

### Guarda de importación

```bash
[[ -n ${_LIB_LOG_LOADED:-} ]] && return 0
readonly _LIB_LOG_LOADED=1
```

Sin ella, un módulo cargado dos veces repite su inicialización y un `readonly` de
primer nivel aborta el script entero.

### Espacios de nombres

Bash no tiene. Se simulan con prefijos, y con disciplina:

| Elemento | Convención | Ejemplo |
|---|---|---|
| Función pública | `module::func` o `module_func` | `log::info` |
| Función privada | `_module_func` | `_log_format` |
| Constante | `MAYÚSCULAS` + `readonly` | `readonly LOG_LEVEL_INFO=2` |
| Variable de módulo | `_MODULE_STATE` | `_LOG_TARGET` |

`log::info` es válido en Bash y se lee muchísimo mejor. `declare -F` lo sigue
viendo, así que el despacho dinámico sigue funcionando.

Cuando algo tiene que quedar **de verdad** aislado, envuélvelo en una subshell:

```bash
resultado=$( set -eu; cd "$dir"; procesar )   # ni el cd ni las variables se escapan
```

Cuesta un fork. Úsalo cuando el aislamiento importe más que la velocidad.

### El patrón "main"

Toda la testabilidad se apoya en separar **definir** de **ejecutar**:

```bash
main() {
	local accion=${1:-help}
	case "$accion" in
		run)  _hacer_algo ;;
		*)    _usage; return 2 ;;
	esac
}

# Con source: solo DEFINE. Ejecutado: CORRE.
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
	main "$@"
fi
```

Un fichero que separa definir de ejecutar se puede cargar desde cualquier sitio.

!!! danger "Esa guarda NO sobrevive a la concatenación"
    Es la guarda que escribe todo el mundo, y por sí sola **no vale para
    empaquetar**. Pega dos módulos que la lleven en un solo fichero y
    `BASH_SOURCE[0]` y `$0` son los dos ese fichero, así que se dispara el
    `main` de todos, en el orden en que estén. Verificado — dos módulos así más
    un despachador, concatenados y ejecutados:

    ```console
    $ bash bundle.sh
    A RAN
    B RAN
    DISPATCHER
    ```

Para empaquetar hace falta una segunda condición: un interruptor que apague la
guarda y que ponga el envoltorio. Por eso todos los scripts de `src/scripts/`
acaban con esto, y no con la forma de dos líneas de arriba:

```bash
# Con source: solo DEFINE. Ejecutado: CORRE.
# Dentro del fichero único DCC_BUNDLE está puesto, así que la guarda se apaga sola.
if [ -z "${DCC_BUNDLE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	main "$@"
fi
```

`build.sh` escribe `DCC_BUNDLE=1` en la cabecera del fichero generado. Los
módulos pegados debajo solo definen, y el despachador que se añade al final es lo
único que corre. Dos ficheros quedan fuera de la regla a propósito:
`bundle-main.sh`, cuya guarda es la inversa (`[ -n "${DCC_BUNDLE:-}" ]`, así que
corre **solo** dentro del bundle), y `common.sh`, que es una biblioteca sin punto
de entrada y sin ninguna guarda.

---

## 4. Testing avanzado con ShellSpec

### Unitario frente a caja negra

| | Unitario (`When call`) | Caja negra (`When run`) |
|---|---|---|
| Subshell | **no** | **sí** |
| Variables tras la llamada | **visibles** | **se pierden** |
| Cobertura de kcov | **se mide** | **también se mide** |
| Para qué | funciones internas | scripts enteros, CLIs |

`When run` sobre una función del proyecto **sí** se mide — verificado: un solo
`When run dex_main` cubrió 31 líneas de `dex.sh`. Lo que kcov no puede ver es un
**proceso** aparte (`When run bash -c …`, o el bundle que lanza
`bundle_spec.sh`), porque instrumenta esta suite y no a sus hijos.

**Hay otros dos puntos ciegos, y tiran en direcciones opuestas.**

Una **función de una línea no entra en el informe siquiera.**
`f() { g; return; }` mete el cuerpo en la línea de la definición, y kcov no
instrumenta ninguna de las dos: la función no sale cubierta ni sin cubrir —
desaparece del denominador. En `ops.sh` es cada
`op_ctx()   { docker context ls; }` del fichero, así que el script queda puntuado
sobre bastantes menos líneas de las que tiene. Escribe esa misma función en tres
líneas y sí aparece: `op_engine()` está en el informe con `hits=0`. La forma
compacta que esta guía defiende más abajo compra legibilidad y la paga en
cobertura que no puedes ver.

El artefacto inverso: **un programa `awk` o `jq` dentro de una cadena de shell se
cuenta como bash.** Esas líneas no se ejecutan nunca como bash, así que salen sin
cubrir por bien probada que esté la función. `dcc_parse_commands()` tiene su
propio `Describe` en `common_spec.sh`; la línea que invoca `awk` marca un montón
de hits y las líneas de programa awk de debajo marcan todas `hits=0`. Igual en
`dashboard.sh`, donde se entra constantemente en `fmt_status()` y todas las
líneas de `awk` de dentro salen a cero — buena parte de por qué el porcentaje de
ese fichero parece bajo, y de por qué partirlo en dos no lo movería ni una línea.

Ejecuta `make coverage` y abre `coverage/index.html` para ver los dos artefactos
tú mismo. No te creas el porcentaje a la primera, ni por arriba ni por abajo.

**Verificado:**

```sh
It 'When call: la variable SOBREVIVE'
  set_it() { SEEN="yes"; }
  When call set_it
  The variable SEEN should eq "yes"
End

It 'When run: la variable NO sobrevive'
  set_it() { SEEN="yes"; }
  When run set_it
  The variable SEEN should be undefined
End
```

**Consecuencia práctica:** si registras las llamadas a un doble en una
**variable** y evalúas con `run`, la aserción "no se llamó a docker" sale verde
aunque sí se llamara. Registra en un **fichero**.

### Doblar comandos externos

```sh
Describe 'deploy'
  Include src/deploy.sh

  setup() {
    LOG="$SHELLSPEC_TMPBASE/calls.log"; : >"$LOG"
    # Doble por función: gratis, y el recomendado.
    curl()      { printf 'curl %s\n'      "$*" >>"$LOG"; printf '{"ok":true}'; }
    systemctl() { printf 'systemctl %s\n' "$*" >>"$LOG"; return 0; }
    docker()    { printf 'docker %s\n'    "$*" >>"$LOG"; return 0; }
  }
  BeforeEach 'setup'

  calls() { [ -s "$LOG" ] && printf '%s' "$(<"$LOG")"; return 0; }

  It 'reinicia el servicio después de desplegar'
    When call deploy v2
    The result of function calls should include "systemctl restart"
  End

  It 'NO toca systemctl si la descarga falla'
    failure() { curl() { return 22; }; deploy v2; }
    When call failure
    The status should be failure
    The result of function calls should be blank
  End
End
```

Dos formas de doblar, y cuándo usar cada una:

| | Función | `Mock … End` |
|---|---|---|
| Coste | ninguno | escribe un script de verdad en el `PATH` |
| Alcance | shell actual y sus subshells | también los procesos hijo (`bash -c`, `xargs`) |
| Cuándo | **por defecto** | el código invoca el comando en otro proceso |

Las dos se restauran al cerrar el bloque: no hay fugas entre ejemplos.

### Afirmar sobre `stderr`, `status` y tus guardas de tipo

```sh
Describe 'assert_is_int()'
  Include src/lib/assert.sh

  Describe 'acepta enteros'
    Parameters
      0
      42
      -7
    End
    It "acepta '$1'"
      When call assert_is_int "$1"
      The status should be success
    End
  End

  Describe 'rechaza con el código semántico correcto'
    Parameters
      "3.14" 64 "un decimal es un TypeError"
      "abc"  64 "el texto es un TypeError"
      ""     67 "vacío es Missing, no Type"
    End
    It "$3"
      When call assert_is_int "$1" edad
      The status should eq "$2"
      The stderr should include "edad"
      The stdout should be blank
    End
  End
End
```

`The stdout should be blank` no es relleno: un validador que ensucia la salida
estándar rompe cualquier `x=$(…)` que lo envuelva.

### Tres trampas verificadas

**1. `Parameters` aplica a TODO el `Describe`, no al `It` siguiente.**

```sh
# MAL: el segundo It hereda la primera tabla y corre 5 veces
Describe 'pct()'
  Parameters … End
  It "…" … End
  Parameters … End      # no sustituye: se fusiona
  It "…" … End
End

# BIEN: cada tabla en su propio Describe anidado
Describe 'pct()'
  Describe 'casos normales'
    Parameters … End
    It "…" … End
  End
  Describe 'casos límite'
    Parameters … End
    It "…" … End
  End
End
```

**2. `Include` resuelve el ámbito de `declare -A`; un `source` a mano no.**
Carga el módulo dentro de `setup()` y el `declare -A` muere al volver (§2), con
lo que el diccionario pasa a indexado en silencio. Usa siempre `Include`.

**3. Los caracteres de control en los argumentos de `When` rompen el reporter.**
Si tu código usa `\x1f` (o cualquier separador de control) y lo pasas por
`When call fn "$SEP" …`, ShellSpec aborta con:

```
reporter.sh: línea 216: field_: orden no encontrada
1 example, 0 failures            <- el test PASA
Fatal error … exit status 102    <- y la ejecución aborta igual
```

Arreglo: que el carácter no cruce la frontera del `When`; úsalo dentro de la
función auxiliar.

### `satisfy` espera un nombre de función

```sh
The output should satisfy [ "$(cat)" -ge 16 ]   # MAL: '[' no es un nombre de función
```

Mueve la condición a una función y afirma el estado:

```sh
It 'devuelve microsegundos'
  is_micros() { local n; n=$(with_epoch); [ "${#n}" -ge 16 ]; }
  When call is_micros
  The status should be success
End
```

---

## 5. Entorno de ingeniería (DX)

### Un `.shellspec` profesional

```
--load-path src/tests
--require spec_helper
--default-path src/tests

# Los scripts usan declare -A, [[ ]] y arrays: bash, no POSIX sh.
--shell bash

# Acota la cobertura o kcov instrumenta al propio ShellSpec.
--kcov-options "--include-path=src/scripts/"
--kcov-options "--exclude-pattern=/src/tests/,/vendor/,.jq"
```

Opciones que conviene conocer, por contexto:

| Opción | Cuándo |
|---|---|
| `--jobs N` | suites grandes; paraleliza **por fichero** |
| `--tag TAG` | ejecutar solo los ejemplos etiquetados (ver el aviso de abajo) |
| `--format documentation` | leer la suite como una especificación |
| `--format tap` / `--format junit` | integración con el CI |
| `--fail-fast` | bucle rojo-verde-refactor |
| `--random examples` | sacar a la luz dependencias ocultas entre ejemplos |

### Separa los tests lentos

**Un solo fichero, `bundle_spec.sh`, se lleva cerca de la mitad del reloj**, en
todas las medidas que ha hecho nadie. Construye el fichero único y lo ejecuta
como proceso aparte, varias veces. Esa proporción es el hallazgo que merece la
pena apuntar.

**Los segundos no, así que esta guía no los publica.** Cronométralos tú cuando
te hagan falta:

```bash
time make test        # todo
time make test-fast   # todo menos bundle_spec.sh
```

Y no apuntes el resultado. Medir esta suite sin tocarle una línea ha dado
tiempos que varían casi **3×** en una sola máquina y en una sola tarde. Una
versión anterior de esta sección publicó un rango que parecía prudente; la
siguiente pasada se salió de él.

`/proc/loadavg` tampoco te salva: es una media de un minuto, así que va por
detrás de una máquina que acaba de quedarse quieta. La pasada más rápida que se
ha registrado aquí marcaba la carga MÁS alta.

Y el paralelismo tampoco: `--jobs` apenas movió el reloj, porque ShellSpec
paraleliza **por fichero** y aquí domina uno. Gana Amdahl. O partes el fichero,
o aceptas el reloj.

Las etiquetas son **argumentos extra del bloque**, no una directiva:

```sh
Describe 'el fichero único' slow:true    # correcto
Describe 'el fichero único'
  Set 'slow:true'                         # MAL: Set es para opciones de shell.
End                                       # Aborta con exit 102.
```

!!! danger "`--tag` solo INCLUYE, no sabe excluir"
    `--tag slow:no` **no** significa "todo menos los lentos". Busca los ejemplos
    cuya etiqueta valga literalmente `slow:no` y devuelve **0 ejemplos**.
    Verificado. Si tu bucle rápido "tarda 5 segundos", comprueba que esté
    ejecutando algo.

Así que el bucle rápido filtra por **fichero**:

```make
test-fast: $(SHELLSPEC)
	@$(SHELLSPEC) $(filter-out %/bundle_spec.sh,$(wildcard $(SRC)/tests/*_spec.sh))
```

```bash
make test-fast                            # el bucle de desarrollo
make test                                 # pre-commit y CI
./vendor/shellspec/shellspec --tag slow   # el bloque etiquetado, a demanda
```

Esa tercera línea lleva su ruta por algo: ShellSpec va **vendorizado, no
instalado**. `make deps` lo deja en `vendor/shellspec/shellspec` y en tu `PATH`
no hay ningún `shellspec` — vale también para cada `shellspec` a secas de la
tabla de opciones de arriba. Y la etiqueta **no** es el complemento exacto de
`test-fast`: `bundle_spec.sh` abre un segundo `Describe` sin etiqueta, así que
`--tag slow` ejecuta menos ejemplos de los que `test-fast` se salta, y esos de
más no son de ninguno de los dos bucles.

!!! tip "Todos los tiempos que ha publicado esta guía acabaron siendo falsos"
    La primera versión citaba dos cifras tomadas con otro cronómetro corriendo
    en paralelo sobre la misma suite: infladas varias veces. La segunda se midió
    con la máquina supuestamente quieta y se dobló en cuanto había un editor
    abierto. La tercera era un *rango* deliberadamente prudente, y la siguiente
    pasada se le escapó.

    La conclusión aguantó siempre: un fichero domina y `--jobs` no lo arregla.
    Los números no aguantaron nunca. Por eso ya no están, y por eso la única
    instrucción que queda aquí es `time make test` en el momento que te importe.

### `shfmt` destroza más de lo que crees

**Verificado.** `shfmt` no entiende `Describe`/`It`/`End` como estructura de
bloques: los trata como órdenes sueltas y desangra todo el DSL a la columna 0.

```diff
 Describe 'best_match()'
-	Include src/scripts/dex.sh
-	best()  { best_match "$1" <<<"$LIST" | cut -f1; }
+Include src/scripts/dex.sh
+best()  { best_match "$1" <<<"$LIST" | cut -f1; }
```

No rompe la ejecución (la sangría es cosmética en shell) pero destruye la
legibilidad del anidamiento, que es justo para lo que sirve el DSL.

**Y no son solo los specs.** Este proyecto excluía `*_spec.sh` y mantenía un
`make fmt` para los scripts — hasta que alguien lo midió: `shfmt -d` daba **1333
líneas de diff en los nueve scripts** sobre un árbol que nadie había tocado
(**1437** hoy, con shfmt 3.13.1 y sus opciones por defecto — la cifra depende de
la versión y de los flags, así que cita los dos). No sabe dejar en paz una
función de una línea:

```diff
-f() { g; return; }
+f() {
+	g
+	return
+}
```

Esa forma compacta es deliberada — es lo que permite leer siete operaciones de
una línea de un vistazo. Así que el target se borró. **Un formateador del que hay
que avisar que no se ejecute no es un formateador.** Aquí la autoridad del estilo
es `shellcheck`: tiene opinión sobre lo correcto y ninguna sobre dónde van tus
llaves.

### Cabecera obligatoria de `shellcheck` en los specs

El DSL dispara siete falsos positivos **inherentes**:

```bash
# shellcheck shell=bash
#
#  Las filas de `Parameters` son DATOS, no órdenes:
#   SC2286  una celda vacía ("") parece un nombre de comando vacío
#   SC2288  una celda que empieza por un carácter raro parece una orden
#   SC2215  una celda como -9000000 parece un flag de comando
#
#  El DSL invoca y comparte estado de forma que shellcheck no puede seguir:
#   SC2317  el cuerpo de una función dentro de un `It` parece inalcanzable
#   SC2329  la misma comprobación con su nombre nuevo, a partir de 0.10.0
#   SC2034  lo que escribe `setup()` se lee en otro bloque
#   SC2154  `MAPA[clave]` es una CLAVE literal, no una variable a resolver
#
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329
```

`SC2317` y `SC2329` son **la misma comprobación renombrada**, así que van las
dos: la 0.9.0 es la que Ubuntu lleva al CI y solo conoce el nombre viejo,
mientras que una 0.11.0 local solo conoce el nuevo. Quita cualquiera de las dos
y la suite pasa el lint en una máquina y falla en la otra.

Desactívalos **en la cabecera del spec**, nunca en un `.shellcheckrc` global —
eso los silenciaría también en el código de producción, que es donde importan.

### Dependencias: mejor un manifiesto verificado

ShellSpec trae un instalador oficial y funciona
(`sh install.sh 0.28.1 --prefix ./vendor`), pero `grep -ci 'sha256|gpg'` sobre él
devuelve **0**: el patrón documentado es `curl … | sh` sin verificación ninguna,
y se guarda los 3,7 MB enteros.

Un manifiesto simple más un instalador pequeño cierra ese agujero y se
generaliza a la siguiente dependencia:

```
# nombre  versión  sha256  url  [rutas,a,conservar]
shellspec 0.28.1 400d8354… https://…/0.28.1.tar.gz shellspec,lib,libexec,helper,stub,bin
```

El instalador verifica el checksum y **aborta sin descomprimir** si no cuadra.
`vendor/` es salida generada y le toca estar en el `.gitignore`, como a `dist/`.
Los gestores de paquetes (`bpkg`, `basher`) no ayudan aquí: primero hay que
instalarlos globalmente, que es una dependencia para gestionar dependencias.

`make deps` vendoriza exactamente una cosa: ShellSpec. Hacen falta otras tres
herramientas que ya tienen que estar en tu máquina, y ninguna está declarada en
`dependencies.txt`:

| Herramienta | La necesita | Si falta |
|---|---|---|
| `shellcheck` | `make lint`, y por tanto `make check` y el hook | Se comprueba antes: sale el mensaje propio del proyecto |
| `kcov` | `make coverage` | Igual: se comprueba antes, mensaje propio |
| `jq` | `make lint`, y por tanto `make check` y el hook | **Sin guarda.** `jq: orden no encontrada` crudo y `make: *** [lint] Error 1` |

Porque `make lint` no es solo shellcheck. Antes de lintar nada valida `bytes.jq`
y `metrics.jq` con `jq -n` — `metrics.jq` con `bytes.jq` delante, porque suelto
falla con *"h/0 is not defined"*. Ese bucle invoca `jq` directamente, así que en una
máquina con el ShellSpec vendorizado pero sin `jq`, `make check` se cae en su
primer target con un error del intérprete y ni una palabra propia del proyecto.
Verificado.

Los submódulos de git se probaron y se descartaron: meten un segundo repositorio
Git dentro del tuyo — paneles duplicados en el editor, un `clone --recursive` que
todo el mundo olvida, y commits accidentales en código ajeno.

### Pipeline de CI

```yaml
# .github/workflows/ci.yml — recortado aquí; el razonamiento está en el fichero real
name: CI
on:
  push: { branches: [main, development] }
  pull_request:

# Sin esto, tres empujones seguidos dejan tres ejecuciones completas corriendo a
# la vez y nadie cancela las viejas. Salvo en main: ahí cada commit quiere el suyo.
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

jobs:
  check:                                 # bash 5, mawk
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: sudo apt-get update && sudo apt-get install -y shellcheck jq
      - run: make check                  # lint y tests detrás de un solo target

      # El empaquetado se comprueba aparte: un fichero único roto no lo detecta
      # nadie hasta que un usuario se lo baja.
      - run: make bundle
      - name: El fichero único arranca fuera del repositorio
        run: cp dist/docker-control-center.sh /tmp/dcc && cd /tmp && ./dcc version

  # El README promete bash 4+. Ejecutarlo solo en el runner —bash 5.2— es
  # verificar la letra de la regla sin correr nunca la configuración prometida.
  #
  # ubuntu:18.04 y NO la imagen `bash:4.4`: esa es Alpine y trae busybox awk, con
  # lo que mezclaría dos incompatibilidades distintas en una sola cruz roja.
  # 18.04 da bash 4.4 con mawk, que es exactamente lo que dice el README.
  #
  # Y `docker run` en vez de `container:`, porque actions/checkout necesita node
  # dentro del contenedor y estas imágenes no lo llevan.
  bash4:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: |
          docker run --rm -v "$PWD:/repo" -w /repo ubuntu:18.04 sh -c '
            apt-get update -qq && apt-get install -y -qq make curl ca-certificates
            # `bash -n` es la parte de `make check` que SÍ depende de la versión:
            # aquí es donde se caza sintaxis de bash 5 colada.
            for f in src/scripts/*.sh src/tests/*.sh build.sh deps.sh; do
              bash -n "$f" || exit 1
            done
            make test
          '

  # El código dice evitar las extensiones de GNU para funcionar igual con mawk
  # que con gawk. Los runners traen mawk, así que gawk no se probaba nunca.
  gawk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: |
          sudo apt-get update && sudo apt-get install -y gawk
          sudo update-alternatives --set awk /usr/bin/gawk
      - run: make test
```

Tres jobs, tres promesas del README. **No hay job de cobertura** a propósito:
kcov se ejecuta en local con `make coverage`, y un número que nadie tiene
permiso para bajar acaba siendo un número que se maquilla.

Probar el bash mínimo no es opcional en una herramienta que anuncia uno. En este
proyecto se coló `EPOCHREALTIME` (bash 5.0) en el código y abortaba un script
entero en bash 4, bajo `set -u`, sin decir por qué. El job `bash4` lo habría
cazado en el primer push.

### Hook de pre-commit

```bash
make hooks     # escribe .git/hooks/pre-commit -> make check
```

`make check` = `lint` + parseo + `test`. Barato de ejecutar, caro de saltarse.

---

## Antipatrones que evitar

| Antipatrón | En su lugar |
|---|---|
| `for f in $(ls *.txt)` | `for f in *.txt; do [[ -e $f ]] \|\| continue` |
| `[ $x = "y" ]` | `[[ $x == "y" ]]` — no parte palabras |
| `expr $a + $b` | `$(( a + b ))` |
| `cat f \| grep x` | `grep x f` |
| `echo $var` | `printf '%s\n' "$var"` — `echo` interpreta escapes según la shell |
| `local x=$(cmd)` | `local x; x=$(cmd)` — si no, se pierde el código de salida |
| `cd dir` sin comprobar | `cd dir \|\| return 1` |
| `[[ $v =~ "$patron" ]]` | `[[ $v =~ $patron ]]` — entrecomillarlo lo hace literal |
| `rm -rf "$DIR/"` con `DIR` posiblemente vacía | `set -u` + `assert_not_empty "$DIR"` |
| Registrar el doble en una variable + `When run` | registrar en un fichero |

---

## Referencia de comandos

```bash
make deps                  # trae vendor/, verificando el sha256
make test                  # la suite entera
make test T=common         # un solo fichero
make test-fast             # todo menos el spec lento del bundle
make lint                  # valida los .jq y luego shellcheck; no hay formateador
make coverage              # kcov -> coverage/
make check                 # lint + parseo + tests: pásalo antes de commitear
```

`deps` necesita red; `lint` y `check` necesitan `shellcheck` **y** `jq`;
`coverage` necesita `kcov`. Lo único que se vendoriza por ti es ShellSpec.
