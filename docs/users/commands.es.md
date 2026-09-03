# Comandos

En el repositorio los comandos del producto pasan por `make run` — el Makefile
solo tiene targets de desarrollo. `make dev <comando>` reconstruye antes el
fichero único. Ejecuta `dcc` sin argumentos y tienes la lista completa con sus
descripciones. Esta página explica los que lo necesitan.

Todo comando que acepta un nombre **abre un menú** si no se lo das —en un
terminal. Sin TTY imprime los candidatos por stderr y sale con `2` en vez de
colgarse. `dex` es la excepción: no abre menú nunca, y sin nombre lista los
contenedores en marcha y sale con `2`.

=== "Repositorio"
    ```bash
    make run logs          # menú para elegir
    make run logs api      # directo
    ```

=== "Fichero único"
    ```bash
    dcc logs               # menú para elegir
    dcc logs api           # directo
    ```

## Panorama

| | |
|---|---|
| `dash` | El panel completo: basura, alertas, stacks, volúmenes, imágenes y disco |
| `dash-fast` | Lo mismo sin tamaños ni disco — la vía rápida |
| `status` | Resumen ejecutivo: la basura contada más el disco de verdad |
| `ps` | Contenedores agrupados por stack, coloreados por gravedad |
| `ram` | RAM que consume el motor, leída de `/proc` |

`dash-fast` es rápido porque se salta las consultas de tamaño y de disco, no
porque tarde siempre lo mismo: sigue listando e inspeccionando todos los
contenedores, así que crece con cuántos tengas y con la latencia del demonio al
que apuntes. La ayuda incorporada aún dice `always ~1s`; detrás de ese número no
hay ninguna medición.

### Leer los colores

El color de un contenedor parado codifica la **gravedad**, no solo si está vivo:

| | |
|---|---|
| Gris `▹` | Salió con código 0 — una parada limpia, **o** sin código que leer |
| Amarillo `▹` | Salió con 137 — SIGKILL, OOM, o una parada que agotó el plazo |
| Rojo `▹` | Cualquier otro código — murió mal |

Ese último caso es el que conviene vigilar. La gravedad sale de buscar
`Exited (N)` en la línea de estado, así que un contenedor en `Restarting (1)`,
`Created` o `Paused` no tiene código que leer y le toca el mismo gris que a una
parada limpia: un crash-loop se ve como un apagado ordenado. La sección de
alertas lee el mismo campo, así que tampoco lo caza.

La columna de CPU enseña un porcentaje **de un núcleo**: 100 % es un núcleo
entero, así que un contenedor que use dos marca 200 %.

## Stacks

`stack-start`, `stack-stop`, `stack-restart`, `stack-logs`, `stack-rm`

!!! info "Por qué no `up` y `down`"
    En compose, `up` y `down` significan CREAR y DESTRUIR. Estos solo arrancan y
    paran contenedores que ya existen. Llamarlos `up` sería mentir. Para crear un
    stack desde cero necesitas su fichero de compose — vete al directorio del
    proyecto.

Los contenedores se buscan **por etiqueta**, no con `docker compose -p`: los
devcontainers de VS Code apuntan a ficheros YAML efímeros que el propio VS Code
borra después, así que cualquier `docker compose` contra ellos falla. La etiqueta
del proyecto siempre está.

## Volúmenes

`volume-inspect`, `volume-tree`, `volume-backup`, `volume-backup-all`,
`volume-restore`, `volumes-orphan`

!!! warning "Sobre las copias de seguridad"
    `volume-backup` escribe el **contenido entero** de tus volúmenes —bases de
    datos incluidas— en un directorio `backups/` **junto a la herramienta**, no
    junto a tu shell. En el repositorio eso es `backups/`, que por eso está en
    el `.gitignore`; instalada como fichero único en `~/.local/bin`, es
    `~/.local/backups`. Para elegir tú el sitio:

    ```bash
    BACKUP_DIR=/ruta/segura dcc volume-backup-all
    ```

    Dos cosas que el ✓ verde no te cuenta. El tar se hace **en caliente** —no se
    para nada y nadie comprueba si el volumen está en uso—, así que un Postgres
    o un MySQL vivo puede salir inconsistente y no restaurar, con un ✓ idéntico
    al de una copia buena. Y el destino es siempre `<nombre>.tar.gz`, así que
    una segunda copia **sobrescribe** la anterior: sin versionar y sin avisar.
    (Una copia que falla se descarta antes de llegar ahí, así que nunca destruye
    la que ya tenías.)
    [Limitaciones](limitations.md#backups-leete-esto-antes-de-fiarte-de-ellos)
    cubre el resto, incluido el contenedor auxiliar.

!!! danger "`volume-restore` borra sin preguntar"
    Es el comando más destructivo de la herramienta —vacía el contenido del
    volumen desde dentro de un contenedor— y no pregunta **nada**: ni
    confirmación, ni marca `DANGER:` en su línea de ayuda, ni comprobación de si
    el volumen está montado. Docker lo monta una segunda vez tan tranquilo, así
    que puedes reemplazar los datos por debajo de un proceso vivo.

    Tampoco **puede restaurar un volumen que has borrado**, que es justo el
    desastre para el que existe la copia. El nombre se valida antes contra
    `docker volume ls -q`, así que un volumen que ya no está recibe
    `There is no volume called 'X'` por stderr y sale con `1` mientras el
    tarball intacto sigue en el directorio de copias. Recréalo y funciona:

    ```bash
    docker volume create mivol && dcc volume-restore mivol
    ```

    Lo que sí comprueba antes de borrar es un `gzip -t` sobre la copia: valida
    el **envoltorio gzip**, no que el tar de dentro esté completo. Extrae a un
    directorio `.dcc-restore` dentro del volumen y solo entonces borra lo viejo,
    así que necesita más o menos el doble del tamaño del volumen libre, y un
    corte entre las dos mitades deja el volumen a medias y ese directorio
    dentro. La copia no se toca nunca.

## Limpieza

`clean` (segura), `clean-build` (caché de construcción), `clean-hard` (pide
confirmación por escrito), `rm-image`

Ninguna toca los volúmenes. Nunca. Eso es todo lo que significa "segura":
`clean` sigue borrando todos los contenedores parados de la máquina, con su capa
de escritura, y no pregunta. De todo lo que en la herramienta destruye o para
algo, solo `stack-rm` y `clean-hard` preguntan antes —
[Limitaciones](limitations.md#comandos-que-destruyen-cosas) tiene la tabla.

## Códigos de salida

La herramienta se encadena, así que los códigos significan algo:

| | |
|---|---|
| `0` | Hecho, **o** el sistema ya estaba así |
| `1` | Lo que has nombrado no existe, o la operación no salió adelante |
| `2` | Error de uso, sin terminal, `backups/` sin permiso, o falta `jq` |
| `3` | Cancelado por quien lo ejecuta, **desde un menú de elección** |

Importan dos distinciones. *"Ya estaba así"* frente a *"no existe"*: un typo tiene
que fallar, un no-op no. Y el `3` frente al `2`: un script que envuelve a esto
necesita distinguir su propio fallo de un humano diciendo que no.

Las dos tienen agujeros. `stop` y `sh` resuelven el nombre solo contra los
contenedores **en marcha**, así que uno que existe pero está parado responde
`There is no running container called 'X'` y sale con `1`: el mensaje es falso, y
`stop` deja de ser idempotente —la segunda llamada falla como si te hubieras
equivocado de nombre—. `start`, `restart`, `logs`, `tail` e `inspect` usan
`docker ps -a` y se comportan como dice la tabla. Y el `2` es más ancho que "lo
has llamado mal": es también lo que devuelve `volume-backup` cuando no puede
escribir en `BACKUP_DIR`, y lo que devuelven `inspect` y `volume-inspect` cuando
falta `jq`.

```bash
dcc stack-start api && ./deploy.sh   # solo despliega si api arrancó de verdad
```

!!! warning "`make run` se come el código de salida"
    En el repositorio, `run` y `dev` acaban en `|| true` para que un `2` de la
    herramienta no lo lea make como una receta rota. Eso significa que `make run`
    sale siempre con `0`. Encadena el fichero único, nunca `make run`.

!!! warning "Las confirmaciones no devuelven `3`, y sin TTY se auto-deniegan"
    `stack-rm` y `clean-hard` te piden teclear una palabra, y decir que no sale
    con `0` — así que `dcc clean-hard && ...` sigue adelante. Solo el menú de
    elección devuelve `3`.

    Y sin terminal es peor. `confirm()` no comprueba que lo haya, así que en un
    script, un cron o el CI la pregunta ni siquiera se enseña: el `read` falla,
    la respuesta vacía no coincide con la palabra, y el comando devuelve `0` sin
    haber hecho nada y sin decir que se canceló. Lo tienes en
    [Limitaciones](limitations.md#sin-terminal-las-confirmaciones-se-auto-deniegan).
