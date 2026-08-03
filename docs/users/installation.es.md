# Instalación

## Un solo fichero

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/dcc
chmod +x dcc && mv dcc ~/.local/bin/
dcc dash
```

Un ejecutable de ~100 KB. Sin nada que instalar y sin dependencias más allá de
`docker`, `bash` y `awk`. Lleva dentro los dos idiomas y todo lo demás.

## Clonando el repositorio

Si quieres tocar el código o generar tú el fichero único:

```bash
git clone https://github.com/velezanthony/docker-control-center
cd docker-control-center
make
```

`make` sin argumentos imprime la lista completa de comandos.

!!! note "La imagen auxiliar"
    La primera vez que uses `volume-tree`, `volume-backup` o `volume-restore`,
    Docker se descargará la imagen `alpine` (unos 8 MB). Es la que se usa para
    operar dentro del volumen. Puedes cambiarla con `HELPER_IMAGE=busybox`.

## Requisitos

**Obligatorio**, y no hay más:

- **Docker Engine nativo**, con el socket accesible por tu usuario
- **bash 4 o superior** (se usan arrays asociativos)
- **awk** — cualquiera. El código evita las extensiones de GNU a propósito, así
  que funciona igual con `mawk` (Debian, Ubuntu) que con `gawk` (Fedora, Arch)
- Las utilidades **POSIX de siempre**: `sed`, `grep`, `sort`, `tr`, `cut`,
  `paste`, `wc`, `du`, `xargs`. Vienen en cualquier Linux; se listan por
  honestidad, no porque haya que instalarlas

**Recomendado.** Si falta alguno la herramienta no se rompe: avisa y sigue
funcionando con menos información.

| Falta | Qué pierdes |
|---|---|
| `curl` | Los tamaños. El panel cae a modo rápido y no muestra disco ni basura |
| `jq` | Lo mismo, **y además** `inspect` y `volume-inspect` dejan de funcionar |
| `tput` | La detección del ancho del terminal; asume 100 columnas |
| `systemd` | Solo el comando `engine` |

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
| **Alpine** | Sin probar. Necesitarías instalar `bash`, y `engine` no funcionará sin systemd |
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
  bash    5.2.21
  docker  /usr/bin/docker
  jq      no instalado
  idioma  es (locale)
  config  /home/tu/.config/dcc/config
```

Es lo primero que hay que mirar cuando algo va raro, y lo primero que te van a
pedir si abres una incidencia.
