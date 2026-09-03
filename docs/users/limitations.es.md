# Limitaciones

Esta página lista lo que la herramienta **no** hace, hace mal, o hace en
silencio cuando debería quejarse. Todo lo de aquí está comprobado contra el
código de esta rama. No es una lista de deseos ni una hoja de ruta: es lo que te
llevas si la instalas hoy. En [Comandos](commands.md) está lo que hace cada uno;
esta página va de dónde se para cada uno.

## Dónde funciona

El objetivo es **Linux con Docker Engine nativo**, hablando con un socket
`unix://` que tu usuario pueda leer. Esa es la única configuración donde
funciona todo.

| | |
|---|---|
| **Linux, motor nativo** | Funciona todo |
| **Docker Desktop, colima, WSL2 con el motor en una VM** | El panel y los comandos funcionan; `ram` y `engine` mienten (abajo) |
| **Docker rootless** | Funciona, pero la columna de CPU cae a `docker stats` y `engine` informa de un estado equivocado |
| **Contextos remotos** (`ssh://`, `tcp://`, `DOCKER_HOST` remoto) | Desaparecen todos los tamaños (abajo) |
| **macOS, Windows** | No. macOS trae bash 3.2 y el código necesita los arrays asociativos de bash 4 |
| **Podman** | No soportado. Nada en el código lo contempla y nunca se ha probado |

### La RAM del motor se lee del `/proc` local

`ram`, y la cifra `RAM host` de la cabecera del panel, recorren `/proc` buscando
`dockerd`, `containerd` y `docker-proxy`. Si el demonio no vive en ese mismo
`/proc` —Docker Desktop, colima, WSL2 con el motor en su propia VM, o cualquier
contexto remoto— el bucle no encuentra nada, el total se queda a cero, y sale
`0.0 MB TOTAL` con código de salida `0`. Eso es indistinguible de un motor que
no consume memoria. No hay ningún aviso.

Con un contexto remoto es peor que cero: el número que ves es la RAM del
`dockerd` **local**, impresa bajo la cabecera del motor remoto.

### `engine` le pregunta a systemd, no a Docker

`engine` ejecuta `systemctl is-active docker`. Cuando falta `systemctl` o el
demonio no lo gestiona el systemd del sistema —Docker Desktop, WSL2, Alpine con
OpenRC, Docker rootless, dentro de un contenedor— la comprobación falla y el
comando imprime `dockerd parado` y te manda ejecutar
`sudo systemctl start docker`, mientras el demonio corre perfectamente.
Comprobado en esta máquina con el demonio vivo y `systemctl` fuera del `PATH`.

### Los contextos remotos pierden todos los tamaños

El panel lee los tamaños de la API de Docker por el socket. El código quita el
prefijo `unix://` y luego exige que lo que queda sea un fichero de socket.
`ssh://host` y `tcp://host:2376` no lo son, así que cae a modo rápido y todas
las secciones que necesitan un tamaño imprimen `Sin datos de tamaño`. `status`
—cuyo trabajo entero es la basura contada más el disco de verdad— queda en dos
líneas de `Sin datos de tamaño`.

El aviso que recibes es `sin socket/curl/jq no hay tamaños`. Con un contexto
remoto los tres están presentes y ninguno es el problema. El CLI de Docker sí
sabría responder con `docker system df`; no hay ningún respaldo hacia él.

### La columna de CPU necesita cgroup v2 en una ruta conocida

La CPU por contenedor se lee directamente de
`system.slice/docker-<id>.scope/cpu.stat` o de `docker/<id>/cpu.stat`. Con
cgroup v1, y con Docker rootless —cuyos scopes cuelgan de
`user.slice/user@UID.service`—, ninguna de las dos rutas existe y el panel cae a
`docker stats --no-stream`. No se rompe nada; `ps` simplemente tarda bastante
más — alrededor del doble en las medidas hechas aquí, aunque los tiempos
absolutos dependen por completo de tu máquina y de lo que esté haciendo.

## Qué necesita

### Obligatorias

Sin esto, los comandos fallan:

| | Lo usa |
|---|---|
| El CLI de `docker` y un demonio accesible | Todo |
| **bash 4 o superior** | Todo — arrays asociativos |
| `awk` | Todo. Sin extensiones de GNU, así que `mawk` y `gawk` se portan igual |
| `sed`, `grep`, `sort`, `tr`, `cut`, `paste`, `wc`, `du`, `xargs` | Varios |
| **`mktemp`** | El panel, `volume-backup`, `lang` |
| **`gzip`** | `volume-restore` |

`mktemp` y `gzip` son dependencias duras y **no están declaradas** en
[Instalación](installation.md). Vienen en cualquier Linux corriente, así que
esto importa sobre todo si ejecutas la herramienta dentro de un contenedor
mínimo.

!!! danger "El mensaje de error puede culpar a quien no es"
    Sin `gzip`, `volume-restore` imprime *«…tar.gz está corrupto (gzip
    inválido). NO se ha borrado nada.»* Acusa a tu backup. El backup está bien;
    lo que falta es una herramienta. Alguien podría borrar un tarball sano por
    esto.

    Sin `mktemp`, el panel imprime errores crudos del intérprete sobre una ruta
    que tú no has elegido (`/stats.txt: Permiso denegado`), pinta medio panel, y
    sale con `0`.

### Opcionales

Si falta una de estas, la herramienta sigue funcionando con menos información:

| Falta | Qué se rompe | Cómo te enteras |
|---|---|---|
| `curl` | Todos los tamaños: disco, basura, tamaño de volúmenes e imágenes | Aviso amarillo, y luego `Sin datos de tamaño` |
| `jq` | Lo mismo, **y además** `inspect` y `volume-inspect` | El mismo aviso; `inspect` dice que necesita `jq` |
| `tput` | La detección del ancho del terminal; se asumen 100 columnas | Nada. En silencio |
| `systemctl` | `engine` informa de un estado equivocado | Nada. Da la respuesta equivocada con total aplomo |
| `getconf` | Se asume un tamaño de página de 4096 | Nada. En kernels con páginas de 16 KB o 64 KB, todas las cifras de RAM salen divididas por ese factor |

Dos asperezas alrededor de esto:

- En `inspect`, la comprobación de `jq` va **después** del menú. Eliges el
  contenedor y solo entonces te dicen que falta `jq`.
- El mensaje dice `sudo apt install jq`. En Fedora, RHEL, Arch, openSUSE o
  Alpine ese comando no existe.

### `dcc version` no cubre los casos confusos

`dcc version` informa de `docker`, `jq`, `curl`, `awk` y `tput`. No dice nada de
`gzip`, `mktemp`, `getconf` ni `systemctl` — que son justo los cuatro cuya
ausencia produce los fallos más engañosos de arriba.

## Comandos que destruyen cosas

Siete comandos borran o paran cosas. **Dos piden confirmación.** Los otros cinco
actúan de inmediato.

| Comando | Qué destruye | ¿Pregunta? |
|---|---|---|
| `stack-rm` | Los contenedores del stack (`docker rm -f`) | **Sí** |
| `clean-hard` | `docker system prune -af` | **Sí** |
| `clean` | Todos los contenedores parados de la máquina, imágenes colgantes y redes sin usar | No |
| `clean-build` | La caché de construcción entera (`builder prune -af`) | No |
| `rm-image` | Una imagen (`docker rmi`) | No |
| `volume-restore` | El contenido actual de un volumen | No |
| `kill-all` | Para todos los contenedores en marcha | No |

Dos cosas de esa tabla que conviene saber:

- **`clean` se anuncia como «seguro».** Eso significa que no toca volúmenes.
  Sigue borrando todos los contenedores parados de la máquina, con su capa de
  escritura, de forma irreversible y sin preguntar.
- **`kill-all` no mata.** Ejecuta `docker stop`: SIGTERM con diez segundos de
  gracia, no SIGKILL. Un contenedor que ignore SIGTERM cuesta diez segundos.

Cuando un comando sí pregunta, quiere la palabra **exacta** tal como se imprime:
`YES` en inglés, `SI` en español, en mayúsculas y sin tilde. `yes`, `si` o `s`
cuentan como un «no».

Decir que no sale con `0`, no con `3`. En
[Comandos](commands.md#codigos-de-salida) están los códigos de salida y dónde
muerde ese en concreto.

## Backups: léete esto antes de fiarte de ellos

Es la parte de la herramienta con más posibilidades de hacerte daño, así que se
lleva el espacio que hace falta.

### Se hacen en caliente

`volume-backup` y `volume-backup-all` ejecutan `tar czf` sobre el volumen
mientras todo sigue corriendo. No se para ningún contenedor. Nada comprueba
siquiera si el volumen está en uso. El tar del directorio de datos de un
Postgres o un MySQL vivo puede salir inconsistente y no restaurar — y el ✓ verde
que recibes es idéntico al de un backup bueno.

Si los datos importan, para tú los contenedores primero.

### Sobrescriben el anterior, sin avisar

El destino es siempre `<directorio de backups>/<nombre del volumen>.tar.gz`. No
hay versionado, ni fecha, ni pregunta. **Cada ejecución destruye el punto de
restauración anterior.** Un backup hecho sobre un volumen roto reemplaza al
bueno de la semana pasada.

### Dónde caen probablemente no es donde crees

El directorio de backups es el **padre** del directorio donde vive la
herramienta, no tu directorio actual. Instalada en `~/.local/bin/dcc`, los
backups van a `~/.local/backups`. Instalada en una ruta del sistema como
`/usr/local/bin`, la herramienta intenta `/usr/local/backups`, que normalmente
necesita root: el comando sale con `2`, el código que la tabla llama error de
uso, para lo que en realidad es un problema de permisos.

Elige tú el sitio:

```bash
BACKUP_DIR=/ruta/segura dcc volume-backup-all
```

Los tarballs se crean legibles solo por ti (`0600`). El directorio se crea con
tu umask, así que en una configuración por defecto otros usuarios locales pueden
listar los **nombres** de tus volúmenes, aunque no leer su contenido.

Interrumpir un backup con Ctrl-C deja atrás un temporal `.backup.XXXXXX`. No hay
ningún manejador que lo limpie.

### `volume-restore` no puede restaurar un volumen que borraste

Esta es la importante. `volume-restore` valida el nombre que le das contra
`docker volume ls -q`. Si el volumen ya no está —el desastre exacto para el que
existe un backup— responde `No hay ningún volumen llamado 'X'.` y sale con `1`,
con el tarball intacto ahí mismo, en el directorio de backups.

El apaño es un comando:

```bash
docker volume create myvol && dcc volume-restore myvol
```

### `volume-restore` no pregunta nada

Es el comando más destructivo de la herramienta —ejecuta `rm -rf` sobre el
contenido del volumen desde dentro de un contenedor— y **no tiene confirmación
de ningún tipo**. Tampoco comprueba si el volumen está montado: Docker lo deja
montar por segunda vez tan contento, y le borras los datos por debajo a un
proceso vivo.

### Comprueba el envoltorio, no el tar

La comprobación previa al borrado es `gzip -t`. Eso valida el **envoltorio
gzip**, no que el archivo de dentro esté completo ni que la extracción vaya a
terminar. El diseño en dos fases sí te protege de una descarga truncada; no
garantiza que el tar esté sano.

### Necesita el doble del espacio libre del volumen

Restore extrae a `/data/.dcc-restore` dentro del propio volumen, luego borra lo
viejo, y luego copia. En un volumen lleno o con cuota, falla. No recibes ningún
aviso previo de ese requisito de espacio.

Si se interrumpe entre las dos mitades, queda un directorio `.dcc-restore`
dentro de tu volumen y el volumen a medias. El backup no se toca.

### El contenedor auxiliar

`volume-tree`, `volume-backup`, `volume-backup-all` y `volume-restore` lanzan un
contenedor auxiliar sobre tu volumen —`volume-backup-all` lanza uno por volumen,
todos por el mismo `backup_one`—. Es `alpine`, una **etiqueta flotante sin fijar**, que se
descarga de Docker Hub la primera vez. En restore el volumen se monta en
**lectura y escritura**, el contenedor corre como root, y le toca la red bridge
por defecto — no hay `--network none`.

La variable `HELPER_IMAGE` decide qué imagen recibe tus volúmenes. Está
documentada como una comodidad; también es lo que conviene mirar con cuidado,
porque `HELPER_IMAGE=otro/loquesea dcc volume-backup-all` mandaría todos los
volúmenes de la máquina a través de una imagen que no has elegido tú.

## Cuando se calla en vez de fallar

### Sin terminal, las confirmaciones se auto-deniegan

`confirm()` lee de la entrada estándar sin comprobar que haya un terminal. En un
script, un cron o en CI, el read falla, la respuesta queda vacía, no coincide
con la palabra exigida, y el comando **devuelve `0` sin haber hecho nada** — y
sin ningún mensaje de «cancelado».

```bash
dcc clean-hard && echo "liberado"   # imprime «liberado». No se liberó nada.
```

Comprobado: con la entrada cerrada, `clean-hard` imprime su aviso rojo, no emite
ni una llamada a Docker, y sale con `0`. El menú de elección sí comprueba si hay
terminal; `confirm()` no.

### `0 MB` de RAM y `Sin datos de tamaño`

Los dos están arriba. Los dos devuelven `0`. Ninguno se distingue de una
respuesta de verdad:

- `ram` imprime `0.0 MB TOTAL` cuando no puede leer el `/proc` del demonio.
- `Sin datos de tamaño` sale allí donde falte un tamaño, sea cual sea la causa:
  falta `curl`, falta `jq`, o es un contexto remoto.

### Con el demonio caído, algunos comandos informan de un estado que no leyeron

`logs`, `stop`, `sh`, `inspect`, `start`, `restart`, `rm-image` y los comandos
`volume-*` pasan todos por el menú de elección, que no comprueba si la llamada a
Docker fue bien. Con el demonio inaccesible te llega el error crudo de Docker a
la pantalla, seguido de `No hay contenedores disponibles.` —o su equivalente de
volúmenes o imágenes—, que es una afirmación sobre un estado que nunca se leyó.
Código de salida `1`.

`stacks`, `networks`, `ctx`, `stats` y `volumes-orphan` te dan solo el error
crudo de Docker y nada propio de la herramienta.

`kill-all` y `dash` lo hacen bien y dicen que el demonio no responde. Ojo a que
`dash` imprime el aviso engañoso de los tamaños **antes** del error de verdad.

### Los argumentos de más se ignoran

Las vistas del panel no reciben sus argumentos. `dcc ps loquesea`,
`dcc status loquesea` y `dcc version loquesea` pintan la salida normal y salen
con `0`, en vez de decirte que el argumento no significa nada.

### Existen dos comandos que la ayuda no menciona nunca

`dcc dashboard` lanza el panel por su interfaz interna `--only`, cuyo valor no
se valida: `dcc dashboard --only=nope` pinta un panel vacío y sale con `0`.
`dcc bundle` se llama a sí mismo sin argumentos e imprime la ayuda. Es
consecuencia de cómo despacha el fichero único; ninguno de los dos está en la
lista de comandos.

### La lista que sale tras un typo está incompleta, y en español

Escribe mal un comando y recibes una línea de uso más una lista de **29** de los
40 comandos. La lista se construye a partir de las operaciones que tienen
función que las implemente, así que faltan las vistas y los comandos internos:
`dash`, `dash-fast`, `status`, `ps`, `psa`, `images`, `volumes`, `dex`, `lang`,
`help` y `version` no están — incluidos el comando estrella y el propio `help`.

La línea de uso de encima está cableada en español. `DCC_LANG=en dcc frobnicate`
imprime `dcc <operación> [preselección]`.

### `stop` sobre un contenedor parado dice que no existe

`stop` y `sh` buscan en la lista de contenedores **en marcha**. Ante un
contenedor que existe pero está parado, responden `No hay ningún contenedor en
ejecución llamado 'X'.` y salen con `1`. El mensaje es falso, y hace que `stop`
no sea idempotente: la segunda llamada falla como si te hubieras equivocado de
nombre.

### Con `$HOME` sin definir aborta antes de arrancar

En un cron sin `HOME`, en una unidad de systemd, con `env -i` o en un contenedor
de CI mínimo, la herramienta muere con un error crudo del intérprete —`HOME:
variable sin asignar`— y código `1`, antes de imprimir una sola palabra suya.
Definir `HOME` o `XDG_CONFIG_HOME` lo evita.

## Salida y terminal

- **Sin soporte de `NO_COLOR` y sin detección de tubería.** Los escapes de color
  son constantes planas que se emiten siempre. Redirige a un fichero o encadena
  con otro comando y los escapes ANSI se van con ellos. `NO_COLOR=1 TERM=dumb`
  no cambia nada. No hay ninguna opción para apagar el color.
- **Las columnas se descuadran fuera de UTF-8.** El relleno cuenta caracteres, y
  en un locale que no sea UTF-8 como `LC_ALL=C` esa cuenta son bytes: cada
  carácter acentuado se come un espacio de relleno. `pad "café" 8` emite cuatro
  espacios finales en UTF-8 y tres en `C`. La interfaz en español —*Volúmenes*,
  *Caché*, *Imágenes*— se tuerce a ojo. Los caracteres de dibujo
  (`─ ● ▸ ⌀ ★ ✓`) también necesitan un terminal UTF-8.
- **El ancho está acotado.** Sale de `tput cols`, o de 100 si falta `tput`, y
  luego se acota entre 60 y 110 columnas. Un terminal de 200 columnas se queda
  en 110; uno de 40 se queda en 60 y hace saltos de línea.

## Todavía no hay release

**El repositorio no tiene ni una etiqueta. Nunca se ha publicado nada.** La URL
de descarga de `releases/latest` no tiene nada que servir.

El único camino de instalación que funciona hoy es clonar y ejecutar
`make link`, como cuenta [Instalación](installation.md). Consecuencias:

- **El symlink es absoluto** y apunta al `dist/` del clon. Mueve el clon,
  renómbralo o bórralo, y `dcc` se convierte en un enlace colgado que muere con
  *«No existe el archivo o el directorio»*. Quedas atado a no tocar el clon de
  sitio.
- **No hay con qué verificar una descarga.** Cuando empiece a haber releases, el
  workflow publica el ejecutable y nada más: ni sha256, ni firma, ni
  attestation. La receta de instalación es descargar un ejecutable con `curl` y
  ejecutarlo.
- **El camino de publicación no ha corrido nunca.** El workflow de release solo
  se dispara con una etiqueta, y no ha habido ninguna. La primera etiqueta será
  su primera ejecución.
- **No hay desinstalador.** Ni `make uninstall`, ni `dcc uninstall`. Quitarla es
  borrar a mano: `~/.local/bin/dcc`, `~/.config/dcc/config`, tus tarballs de
  backup, y —en el clon— `vendor/`, `dist/`, `coverage/` y el
  `.git/hooks/pre-commit` que instala `make hooks`.

## Idioma

La interfaz está en **inglés y español**, y solo en esos dos. En
[Idioma](language.md) está cómo se elige.

**Un valor que no reconoce cae a inglés sin decir una palabra.** `DCC_LANG=fr`
te da inglés, y `dcc version` informa luego de `language en (env)`: el origen
es correcto, pero el valor que pusiste no se te devuelve nunca y ningún aviso
dice que se descartó.

Hay texto que sale en inglés elijas lo que elijas:

- Los nombres de los comandos.
- Todo lo que imprime Docker de pasada: `ctx`, `stats`, `logs`, `tail`,
  `rm-image`, `volume-tree`, y el `docker system df` que va detrás de los
  comandos de limpieza.
- Las cabeceras de columna de `stats`, porque le pide a Docker una tabla ya
  formateada y esas cabeceras las escribe Docker. `networks` evita esto a
  propósito, así que los dos comandos son incoherentes entre sí.

Y hay texto que sale en español elijas lo que elijas: la línea de uso tras un
typo, y cuatro mensajes de error internos que no pasan por el catálogo.

En este sitio, *Cómo contribuir*, *Cambios* y *Seguridad* existen solo en
inglés. La etiqueta de navegación está traducida; la página a la que llegas, no.
