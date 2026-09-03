#!/usr/bin/env bash
# common.sh — runtime compartido y único punto de entrada de los demás scripts.
# Sin `set -e`: pick() y confirm() devuelven != 0 como respuesta legítima.
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2209,SC1090,SC2059,SC2031  # es una BIBLIOTECA

DCC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DCC_ROOT=$(cd "$DCC_DIR/.." && pwd)

R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
CY=$'\033[36m'; GR=$'\033[32m'; YE=$'\033[33m'; RD=$'\033[31m'

DCC_VERSION="0.9.0"

# `make run <comando>` en el repo y `dcc <comando>` en el bundle. `make` a secas
# no vale: el Makefile no tiene NI UN target de producto.
DCC_CMD=${DCC_CMD:-make run}

# DCC_BUNDLE lo pone el fichero único, y hace dos cosas: cambia la cabecera de
# la ayuda y apaga la guarda del final de cada script — allí todo vive en un
# fichero, así que BASH_SOURCE[0] y $0 coinciden siempre.
DCC_USAGE_KEY=help_usage
DCC_HINT_KEY=help_hint
if [ -n "${DCC_BUNDLE:-}" ]; then
	DCC_USAGE_KEY=help_usage_bundle
	DCC_HINT_KEY=help_hint_bundle
fi

W_SERVICE=20   # servicio o contenedor
W_STATUS=15    # "up 3h", "exit 137 2d"
W_CPU=6        # "12.5%"
W_PORTS=12     # "8085→8080"
W_IMAGE=26     # repo:tag
W_STACK=26     # proyecto compose
W_VOLUME=42    # volumen (los de compose son largos)
W_LABEL=18     # etiquetas de basura y disco
W_DETAIL=26    # detalle de esa sección
W_TARGET=18    # target en `make help`
W_NAME=26      # nombre en redes
W_DRIVER=10    # driver en redes
W_SIZE=9       # tamaño a la derecha ("12.25 GB")
W_ALERT=28     # etiqueta de alerta
W_REPO=56      # repo:tag en imágenes

# 0x1f y NO tabulador: bash colapsa los IFS que son espacio en blanco, y dos tabs
# seguidos cuentan como uno — los campos vacíos desplazan la fila entera.
SEP=$'\x1f'

# printf "%-Ns" cuenta BYTES; ${#s} cuenta caracteres. Úsalo para texto de usuario.
pad() {
	local s=$1 w=$2 n=${#1}
	if (( n > w )); then printf '%s…' "${s:0:w-1}"
	else printf '%s%*s' "$s" $((w - n)) ''
	fi
}
rpad() { local s=$1 w=$2 n=${#1}; (( n < w )) && printf '%*s' $((w - n)) ''; printf '%s' "$s"; }

# `paste -sd', '` no vale: -d es una LISTA que ROTA y con tres da "a,b c".
join_list() { paste -sd, - | sed 's/,/, /g'; }

# Idioma: DCC_LANG del entorno > .config > LC_ALL/LC_MESSAGES/LANG > en.
# El fichero existe porque un hijo no puede cambiarle el entorno a su padre.
DCC_CONFIG=${DCC_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/dcc/config}

# Sin `source`: la configuración no debe poder ejecutar código.
_dcc_cfg_get() {
	local want=$1 line key val
	# -f y no solo -r, que es CIERTO para un directorio y el read reventaba.
	[ -f "$DCC_CONFIG" ] && [ -r "$DCC_CONFIG" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		line=${line%%#*}
		[[ $line == *=* ]] || continue
		key=${line%%=*}; val=${line#*=}
		key=${key//[[:space:]]/}; val=${val//[[:space:]]/}
		val=${val%\"}; val=${val#\"}; val=${val%\'}; val=${val#\'}
		if [ "$key" = "$want" ] && [ -n "$val" ]; then printf '%s' "$val"; return 0; fi
	done <"$DCC_CONFIG"
	return 1
}

# A memoria: el bundle no tiene ficheros .jq que ofrecer.
if [ -z "${JQ_BYTES:-}" ] && [ -r "$DCC_DIR/bytes.jq" ]; then
	JQ_BYTES=$(<"$DCC_DIR/bytes.jq")
fi
if [ -z "${JQ_METRICS:-}" ] && [ -r "$DCC_DIR/metrics.jq" ]; then
	JQ_METRICS="${JQ_BYTES:-}"$'\n'"$(<"$DCC_DIR/metrics.jq")"   # bytes.jq define h()
fi
: "${JQ_BYTES:=}" "${JQ_METRICS:=}"

# FUERA de la función: un `declare -A` dentro sería LOCAL y moriría al volver.
declare -A MSG

# En una función para poder recargar: lang.sh la repite tras guardar la preferencia.
dcc_load_language() {
	local raw=""
	if [ -n "${DCC_LANG:-}" ]; then
		raw=$DCC_LANG; DCC_LANG_ORIGIN=env
	elif raw=$(_dcc_cfg_get DCC_LANG); then
		DCC_LANG_ORIGIN=config
	elif [ -n "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" ]; then
		raw=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}; DCC_LANG_ORIGIN=locale
	else
		DCC_LANG_ORIGIN=default
	fi

	case "${raw,,}" in
		es | es[_.-]* | *[._]es | *[._]es[._]*) DCC_LANG_RESOLVED=es ;;
		*) DCC_LANG_RESOLVED=en ;;
	esac

	MSG=()
	local cat="$DCC_ROOT/i18n/$DCC_LANG_RESOLVED.sh"
	# Incrustados en el bundle, ficheros en el repo. En ese orden.
	if declare -F "_catalog_$DCC_LANG_RESOLVED" >/dev/null 2>&1; then
		"_catalog_$DCC_LANG_RESOLVED"
	elif [ -f "$cat" ] && [ -r "$cat" ]; then
		# Descartar entero es mejor que dejar MSG a medias.
		if bash -n "$cat" 2>/dev/null; then
			# shellcheck source=/dev/null
			. "$cat"
		else
			printf 'dcc: %s tiene un error de sintaxis; se ignora\n' "$cat" >&2
		fi
	fi
}

# --- Docker: lo poco que comparten dex.sh y ops.sh ----------------------------
# Aquí y no en ops.sh porque el orden de carga del bundle pone dex ANTES que ops.

dcc_names()     { docker ps    --format '{{.Names}}'; }
dcc_names_all() { docker ps -a --format '{{.Names}}'; }

# `-t` solo con terminal en AMBOS extremos: en una tubería `docker exec -it`
# aborta con "the input device is not a TTY". Sin comando abre una shell,
# prefiriendo bash y cayendo a sh.
dcc_exec() {
	local name=$1; shift
	local flags=(-i)
	[ -t 0 ] && [ -t 1 ] && flags=(-i -t)
	if [ "$#" -eq 0 ]; then
		docker exec "${flags[@]}" "$name" sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'
	else
		docker exec "${flags[@]}" "$name" "$@"
	fi
}

dcc_version_info() {
	printf "${B}%s${R} %s\n" "$(t help_title)" "$DCC_VERSION"
	printf "  %-8s %s\n" "bash" "${BASH_VERSION%%(*}"
	local c
	for c in docker jq curl awk tput; do
		if command -v "$c" >/dev/null; then printf "  %-8s %s\n" "$c" "$(command -v "$c")"
		else printf "  ${YE}%-8s %s${R}\n" "$c" "$(t not_installed)"; fi
	done
	# La etiqueta se traduce: "language" mide 8 y por eso la columna es 8, no 7.
	printf "  %-8s %s (%s)\n" "$(t version_language)" "$DCC_LANG_RESOLVED" "$DCC_LANG_ORIGIN"
	printf "  %-8s %s\n" "config" "$DCC_CONFIG"
}

# El formato `nombre: ## texto`, con secciones `##@`, se parsea AQUÍ y en ningún
# otro sitio: con más de una regla, la ayuda acaba prometiendo comandos que
# dispatch rechaza por desconocidos.
#
# $1 = names (solo el nombre) · lines (secciones + comandos). Lee de la entrada
# estándar: así se le da un fichero o la variable que el bundle lleva dentro.
dcc_parse_commands() {
	awk -v mode="${1:-lines}" '
		/^##@ /                { if (mode != "names") print; next }
		/^[a-z][a-z0-9-]*:.*##/ { if (mode == "names") { sub(/:.*/, ""); print } else print }
	'
}

# Lo que la herramienta ANUNCIA: fichero en el repositorio, variable incrustada
# en el bundle — la misma dualidad que los catálogos. Se cachea porque dispatch
# lo consulta dos veces por invocación y cada una eran dos forks.
DCC_ANNOUNCED_CACHE=""
dcc_announced() {
	[ -n "$DCC_ANNOUNCED_CACHE" ] || DCC_ANNOUNCED_CACHE=$(
		if [ -n "${DCC_HELP_SRC:-}" ]; then
			printf '%s\n' "$DCC_HELP_SRC"
		else
			cat "$DCC_ROOT/commands.txt" 2>/dev/null
		fi | dcc_parse_commands names
	)
	printf '%s\n' "$DCC_ANNOUNCED_CACHE"
}

# Aquí y no en lang.sh: la fuente cambia entre repo y bundle.
dcc_languages() {
	if declare -F _catalog_en >/dev/null 2>&1; then
		declare -F | awk '$3 ~ /^_catalog_/ { sub(/^_catalog_/, "", $3); print $3 }' | sort
	else
		local f
		for f in "$DCC_ROOT"/i18n/*.sh; do [ -e "$f" ] && basename "$f" .sh; done
	fi
}

dcc_language_name() {
	if declare -F "_catalog_$1" >/dev/null 2>&1; then
		# La subshell aísla el catálogo ajeno del MSG activo.
		# shellcheck disable=SC2030,SC2031
		( declare -A MSG=(); "_catalog_$1"; printf '%s' "${MSG[lang_name]-}" )
	else
		awk -F'"' '/\[lang_name\]=/ { print $2; exit }' "$DCC_ROOT/i18n/$1.sh" 2>/dev/null
	fi
}

dcc_load_language

t()   { printf '%s' "${MSG[$1]-$1}"; }                          # literal
tf()  { local _k=$1; shift; printf "${MSG[$_k]-$_k}" "$@"; }    # con formato printf
say() { tf "$@"; printf '\n'; }                                 # tf + salto de línea

true
