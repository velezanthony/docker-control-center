#!/usr/bin/env bash
# deps.sh — descarga a vendor/ lo que dice dependencies.txt.  [--force reinstala]
#
# No es un submódulo a propósito: metería un segundo repositorio git dentro del
# tuyo, con paneles duplicados en el editor y commits accidentales en código
# ajeno. El sha256 se verifica SIEMPRE y se aborta sin descomprimir si no cuadra.
# El color va en el formato de printf, como en todo el proyecto.
# shellcheck disable=SC2059
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST="$ROOT/dependencies.txt"
VENDOR="$ROOT/vendor"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'; GR=$'\033[32m'; RD=$'\033[31m'; YE=$'\033[33m'

die() { printf "${RD}%s${R}\n" "$*" >&2; exit 1; }

[ -r "$MANIFEST" ] || die "No encuentro $MANIFEST"
command -v curl >/dev/null || die "Hace falta curl para descargar las dependencias."
command -v tar  >/dev/null || die "Hace falta tar."

# sha256sum (coreutils) o shasum (BSD/macOS). Uno de los dos hay siempre.
if command -v sha256sum >/dev/null; then
	sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null; then
	sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
	die "No encuentro sha256sum ni shasum: no puedo verificar lo que descargo."
fi

install_one() {
	local name=$1 version=$2 want=$3 url=$4 keep=${5:-}
	local dest="$VENDOR/$name"

	if [ -e "$dest/.version" ] && [ "$(<"$dest/.version")" = "$version" ] && [ "$FORCE" = 0 ]; then
		printf "  ${D}%-12s %-10s ya está${R}\n" "$name" "$version"
		return 0
	fi

	printf "  ${B}%-12s %-10s${R} descargando… " "$name" "$version"

	local tmp; tmp=$(mktemp -d) || die "No puedo crear un temporal"
	trap 'rm -rf "$tmp"' RETURN

	curl -fsSL -o "$tmp/pkg.tar.gz" "$url" || die "fallo la descarga de $url"

	local got; got=$(sha256 "$tmp/pkg.tar.gz")
	if [ "$got" != "$want" ]; then
		printf "\n"
		printf "${RD}  El sha256 de %s NO cuadra. No descomprimo nada.${R}\n" "$name" >&2
		printf "${RD}    esperado: %s${R}\n" "$want" >&2
		printf "${RD}    obtenido: %s${R}\n" "$got"  >&2
		printf "${YE}  Si has subido la versión a mano, actualiza también el sha256.${R}\n" >&2
		exit 1
	fi

	# --strip-components=1: los tarballs de GitHub traen todo bajo <repo>-<tag>/.
	mkdir -p "$tmp/x"
	tar xzf "$tmp/pkg.tar.gz" -C "$tmp/x" --strip-components=1 || die "no puedo descomprimir $name"

	# Se guarda solo lo que la dependencia declara en la 5ª columna del
	# manifiesto: de ShellSpec el runtime son ~1 MB frente a 3,7 MB de
	# repositorio con docs, ejemplos y sus propios tests. Sin lista, todo.
	rm -rf "$dest"; mkdir -p "$dest"
	if [ -n "$keep" ]; then
		local p
		for p in ${keep//,/ }; do
			[ -e "$tmp/x/$p" ] && cp -r "$tmp/x/$p" "$dest/"
		done
	else
		cp -r "$tmp/x/." "$dest/"
	fi

	printf '%s\n' "$version" >"$dest/.version"
	printf "${GR}ok${R} ${D}(sha256 verificado)${R}\n"
}

printf "\n  ${B}Dependencias de desarrollo${R} ${D}(vendor/, generado — no se versiona)${R}\n\n"

mkdir -p "$VENDOR"
found=0
while read -r name version want url keep; do
	case "${name:-}" in ''|\#*) continue ;; esac
	[ -n "${url:-}" ] || die "Línea mal formada en dependencies.txt: $name"
	found=1
	install_one "$name" "$version" "$want" "$url" "${keep:-}"
done <"$MANIFEST"

[ "$found" = 1 ] || die "dependencies.txt no declara ninguna dependencia."
printf "\n"
