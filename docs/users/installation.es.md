# Instalación

## Clonando el repositorio

Hoy es la única forma: el repositorio no tiene ninguna etiqueta, así que
`releases/latest` todavía no tiene nada que servir.

```bash
git clone https://github.com/velezanthony/docker-control-center
cd docker-control-center
make link
```

`make link` deja un enlace simbólico en `~/.local/bin`, así que un `make bundle`
posterior actualiza `dcc` solo.

Ese enlace es **absoluto** y apunta dentro del clon
(`<clon>/dist/docker-control-center.sh`). Si mueves el clon, lo renombras o lo
borras, `dcc` se queda colgando y muere con *«No such file or directory»*;
se arregla volviendo a lanzar `make link` desde la nueva ubicación. El
directorio de destino es `LINK_DIR` si lo defines, y si no está en tu `PATH`,
`make link` te avisa y te dice qué añadir.

`make` sin argumentos imprime los targets de **desarrollo** — el Makefile no
tiene ni un comando de producto. Para la lista de comandos, ejecuta `dcc` (o
`make run`) sin argumentos.

## Un solo fichero

A partir de la primera publicación:

!!! warning "Hoy no funciona, y falla en silencio"
    Sin etiquetas no hay nada detrás de `releases/latest`. La URL responde
    `404`, y `curl -LO` no lo considera un error: comprobado hoy, escribe un
    fichero de 9 bytes llamado `dcc` cuyo contenido es `Not Found` y sale con
    `0`. Las dos líneas siguientes le dan permiso de ejecución a ESE fichero y
    lo dejan en tu `PATH`. Añade `-f` si quieres que `curl` falle de verdad.

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/dcc
chmod +x dcc && mv dcc ~/.local/bin/
dcc dash
```

Un ejecutable de menos de 90 KB. Sin nada que instalar: lleva dentro los dos
idiomas y todo lo suyo. Lo que no lleva son las utilidades del sistema de los
Requisitos. Y nadie va a verificarte la descarga: no hay sha256 ni firma
([Limitaciones](limitations.md#todavia-no-hay-release)).

!!! note "La imagen auxiliar"
    La primera vez que uses `volume-tree`, `volume-backup`, `volume-backup-all`
    o `volume-restore`, Docker se descargará la imagen `alpine` — 3,9 MB de descarga y 13 MB en
    disco, medidos con `docker image ls` sobre amd64. Es la que se usa para
    operar dentro del volumen. Puedes cambiarla con `HELPER_IMAGE=busybox`.

## Requisitos

**Obligatorio.** Esta es la lista corta;
[Limitaciones](limitations.md#que-necesita) tiene la completa, con dos
dependencias duras cuya ausencia produce un mensaje que culpa a quien no debe.

- **Docker Engine nativo**, con el socket accesible por tu usuario
- **bash 4 o superior** (se usan arrays asociativos)
- **`$HOME` o `$XDG_CONFIG_HOME` definidas**. La ruta del fichero de
  configuración se resuelve al arrancar bajo `set -u`, así que sin ninguna de
  las dos la herramienta muere con un `HOME: variable sin asignar` crudo del
  intérprete y sale con `1` antes de imprimir una sola palabra suya —
  `dcc version` incluido. Muerde en tareas de cron, unidades de systemd,
  `env -i` y contenedores de CI mínimos, donde el entorno no es el que te da tu
  shell
- **awk** — cualquiera. El código evita las extensiones de GNU a propósito, así
  que funciona igual con `mawk` (Debian, Ubuntu) que con `gawk` (Fedora, Arch)
- Las utilidades **POSIX de siempre**: `sed`, `grep`, `sort`, `tr`, `cut`,
  `paste`, `wc`, `du`, `xargs`. Vienen en cualquier Linux; se listan por
  honestidad, no porque haya que instalarlas

**Recomendado.** Que falte alguno no rompe la herramienta, pero solo los dos
primeros te dicen que faltan; los demás se callan y siguen.

| Falta | Qué pierdes |
|---|---|
| `curl` | Los tamaños. El panel cae a modo rápido y no muestra disco ni basura. Avisa |
| `jq` | Lo mismo, **y además** `inspect` y `volume-inspect` dejan de funcionar. Avisa |
| `tput` | La detección del ancho del terminal; asume 100 columnas. En silencio |
| `systemctl` | El comando `engine`, que no degrada: MIENTE. Le pregunta a systemd en vez de a Docker, así que con el demonio perfectamente vivo imprime `○ dockerd parado` **y** `NO arranca al inicio`, y nada dice que lo que falta es `systemctl`. Verificado hoy en esta máquina ([Limitaciones](limitations.md#engine-le-pregunta-a-systemd-no-a-docker)) |
| `getconf` | Nada que se vea: se asume que la página de memoria mide 4096, así que en un núcleo con páginas de 16 KB o 64 KB todas las cifras de RAM se van por ese factor |

```bash
sudo apt install jq curl        # Debian / Ubuntu
sudo dnf install jq curl        # Fedora / RHEL
sudo pacman -S jq curl          # Arch
```

Para usar Docker sin `sudo`:

```bash
sudo usermod -aG docker $USER   # cierra sesión y vuelve a entrar
```

## Sistemas

| | |
|---|---|
| **Cualquier distro Linux** | Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE… |
| **Alpine** | Sin probar. Necesitarías instalar `bash`, y con OpenRC en vez de systemd `engine` dirá que el demonio está parado teniéndolo vivo |
| **macOS** | No. Trae bash 3.2 y no hay Docker Engine nativo |
| **Windows** | No |

Desarrollado y probado sobre Ubuntu, pero no depende de nada específico de
Ubuntu. No hace falta `procps`: la RAM del motor se lee de `/proc` en bash puro.

## Comprobar tu instalación

```bash
dcc version
```

```
Docker Control Center 0.9.0
  bash     5.2.21
  docker   /usr/bin/docker
  jq       no instalado
  curl     /usr/bin/curl
  awk      /usr/bin/awk
  tput     /usr/bin/tput
  idioma   es (locale)
  config   /home/tu/.config/dcc/config
```

Es lo primero que hay que mirar cuando algo va raro, y lo primero que te van a
pedir si abres una incidencia. Fíjate en lo que NO comprueba: `gzip`, `mktemp`,
`getconf` y `systemctl` no salen en esa lista, y son justo aquellos cuya
ausencia produce los fallos más confusos
([Limitaciones](limitations.md#dcc-version-no-cubre-los-casos-confusos)).

## Desinstalar

No hay `make uninstall` ni `dcc uninstall`. Se quita a mano, y estos son los
ficheros que deja:

```bash
rm ~/.local/bin/dcc              # el enlace (o el ejecutable copiado)
rm -rf ~/.config/dcc             # solo existe si ejecutaste `dcc lang`
docker image rm alpine           # la imagen auxiliar, si usaste volume-*
```

Tus copias de seguridad **no** están en ninguno de esos sitios: caen al lado
del directorio desde el que se ejecuta la herramienta —`~/.local/backups` con
la instalación de arriba— salvo que definas `BACKUP_DIR`. Míralo antes de
borrar nada, y lee
[Limitaciones](limitations.md#donde-caen-probablemente-no-es-donde-crees).

Si clonaste el repositorio, borrar el clon se lleva el resto por delante:
`dist/`, y `vendor/`, `coverage/` y el `.git/hooks/pre-commit` que crean
`make deps`, `make coverage` y `make hooks`.
