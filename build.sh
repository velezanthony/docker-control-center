#!/usr/bin/env bash
# build.sh — genera dist/: la herramienta entera en UN fichero, concatenando.
# DCC_BUNDLE apaga la guarda de todos los módulos, así que pegados solo DEFINEN
# y al final se añade un despachador. Catálogos, .jq y ayuda van incrustados.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$ROOT/src
# Quien lo instale puede renombrarlo: la ayuda se adapta al nombre del fichero.
OUT=${1:-$ROOT/dist/docker-control-center.sh}
mkdir -p "$(dirname "$OUT")"

# Se CARGA el runtime: de aquí salen DCC_VERSION y dcc_parse_commands(). Un
# empaquetador con su propia idea del formato acaba metiendo en el bundle algo
# que la herramienta no sabe ejecutar.
# shellcheck source=src/scripts/common.sh
. "$SRC/scripts/common.sh"
VERSION=$DCC_VERSION

# El despachador va SIEMPRE el último y por eso se saca del descubrimiento
# automático: si entrara por el glob, un `zz-loquesea.sh` nuevo caería detrás y
# bundle_main se ejecutaría antes de que ese módulo estuviera definido.
DISPATCHER=bundle-main

# El orden de carga, a mano y completo. Manda sobre el ORDEN, no sobre la
# pertenencia: lo que no se nombre entra igual, al final y por orden alfabético.
BUNDLE_ORDER=(
	common         # colores, SEP, pad(), rutas e i18n: lo carga todo lo demás
	engine-ram     # engine_ram()    <- dashboard.sh, ops.sh
	container-cpu  # container_cpu() <- dashboard.sh
	help           # render_help()   <- el despachador del final
	dashboard      # dcc_view_sections() <- el despachador del final
	dex
	lang
	ops            # cierra: dispatch() deriva su tabla de las op_* ya definidas
)

# En el SHELL ACTUAL y antes de escribir un byte: desde `< <(...)` el `exit 1`
# moriría en la subshell y se escribiría un bundle incompleto con código 0.
MODULES=()
resolve_modules() {
	local m f name
	for m in "${BUNDLE_ORDER[@]}"; do
		[ -r "$SRC/scripts/$m.sh" ] || {
			printf 'build.sh: BUNDLE_ORDER nombra %s.sh y no existe\n' "$m" >&2
			return 1
		}
		MODULES+=("$m")
	done
	for f in "$SRC"/scripts/*.sh; do
		name=$(basename "$f" .sh)
		[ "$name" = "$DISPATCHER" ] && continue
		printf '%s\n' "${BUNDLE_ORDER[@]}" | grep -qxF "$name" && continue
		MODULES+=("$name")
	done
	[ -r "$SRC/scripts/$DISPATCHER.sh" ] || {
		printf 'build.sh: falta el despachador %s.sh\n' "$DISPATCHER" >&2
		return 1
	}
}
resolve_modules || exit 1

# Solo COMENTARIOS, nunca código: si una de estas dos reglas falla sobra un
# comentario, no sale un bundle roto.
strip_comments() {
	awk '
		NR == 1 && /^#!/ { next }
		/^# shellcheck source=/ { next }
		{ print }
	' "$1"
}

{
	cat <<EOF
#!/usr/bin/env bash
# ==============================================================================
#  Docker Control Center $VERSION — fichero único, generado automáticamente.
#
#  NO EDITES ESTO: se regenera con 'make bundle' y tus cambios se pierden.
#
#  Uso:  ./docker-control-center.sh          (ayuda)
#        ./docker-control-center.sh dash
#
#  Puedes renombrarlo: la ayuda se adapta al nombre del fichero.
#  Configuración e idioma:  ~/.config/dcc/config
# ==============================================================================
set -uo pipefail

DCC_BUNDLE=1
DCC_CMD=\${DCC_CMD:-\$(basename "\$0" .sh)}
EOF

	printf '\n# --- bytes.jq ---\nJQ_BYTES=%s\n' "$(printf '%q' "$(<"$SRC/scripts/bytes.jq")")"
	printf '\n# --- metrics.jq (con bytes.jq delante) ---\nJQ_METRICS=%s\n' \
		"$(printf '%q' "$(<"$SRC/scripts/bytes.jq")"$'\n'"$(<"$SRC/scripts/metrics.jq")")"

	for cat in "$SRC"/i18n/*.sh; do
		code=$(basename "$cat" .sh)
		printf '\n# --- catálogo %s ---\n_catalog_%s() {\n' "$code" "$code"
		sed 's/^/\t/' "$cat"
		printf '}\n'
	done

	for m in "${MODULES[@]}"; do
		printf '\n# --- %s.sh ---\n' "$m"
		strip_comments "$SRC/scripts/$m.sh"
	done

	# La ayuda sale de src/commands.txt, que solo describe el producto: del
	# Makefile saldrían lint, test y check, que el fichero único no tiene.
	printf '\n# --- ayuda (src/commands.txt) ---\nDCC_HELP_SRC=%s\n' \
		"$(printf '%q' "$(dcc_parse_commands lines <"$SRC/commands.txt")")"

	# El despachador, el ÚLTIMO: cuando se ejecuta ya está todo definido.
	printf '\n# --- %s.sh (el despachador) ---\n' "$DISPATCHER"
	strip_comments "$SRC/scripts/$DISPATCHER.sh"
} >"$OUT.tmp"

# Aparte y luego mv (atómico): un fallo a mitad dejaría un $OUT truncado.
mv "$OUT.tmp" "$OUT"
chmod +x "$OUT"
printf '%s  (%s líneas, %s)\n' "$OUT" "$(wc -l <"$OUT")" "$(du -h "$OUT" | cut -f1)"
