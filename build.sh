#!/usr/bin/env bash
# build.sh — genera dist/: la herramienta entera en UN fichero. Es una
# concatenación: la guarda BASH_SOURCE hace que pegados solo DEFINAN, y al final
# se añade un despachador. Catálogos, .jq y ayuda van incrustados.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$ROOT/src
# Quien lo instale puede renombrarlo: la ayuda se adapta al nombre del fichero.
OUT=${1:-$ROOT/dist/docker-control-center.sh}
mkdir -p "$(dirname "$OUT")"

VERSION=$(awk -F'"' '/^DCC_VERSION=/ {print $2; exit}' "$SRC/scripts/common.sh")

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
		printf '%s\n' "${BUNDLE_ORDER[@]}" | grep -qxF "$name" && continue
		MODULES+=("$name")
	done
}
resolve_modules || exit 1

# Quita shebang, guarda final y `source` de hermanos. Casa LÍNEAS EXACTAS:
# partirlas deja el bundle roto con el repositorio en verde (ver bundle_spec.sh).
#
# El source indentado se SUSTITUYE por `:` en vez de borrarse: es el único
# cuerpo de un `if … then`, y quitarlo deja un bloque vacío que bash no parsea.
# Y sin anclar al principio ni clases de caracteres: el patrón llevaba `\s`, que
# no es POSIX —mawk no lo entiende y gawk sí—, y `[[:space:]]` tampoco vale
# porque mawk 1.3.3 (Ubuntu 18.04) no lo soporta. Tres awks, tres resultados
# distintos: en unos la línea sobrevivía y en otros dejaba el `if` vacío.
strip_module() {
	awk '
		NR == 1 && /^#!/ { next }
		/^# shellcheck source=src\/scripts\// { next }
		/^\. "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)\/common\.sh"$/ { next }
		/\. "\$DCC_DIR\/[a-z-]+\.sh"$/ { print "\t:"; next }
		/^if \[ "\$\{BASH_SOURCE\[0\]\}" = "\$\{0\}" \]; then$/ { skip = 1; next }
		skip && /^fi$/ { skip = 0; next }
		skip { next }
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
		strip_module "$SRC/scripts/$m.sh"
	done

	# La ayuda sale de src/commands.txt, que solo describe el producto. Antes se
	# extraía del Makefile y había que recortarlo por BUNDLE-EXCLUDE para no
	# prometer lint, test y check, que el bundle no tiene.
	printf '\n# --- ayuda (src/commands.txt) ---\nDCC_HELP_SRC=%s\n' \
		"$(printf '%q' "$(grep -E '^##@ |^[a-zA-Z0-9_-]+:.*##' "$SRC/commands.txt")")"

	cat <<'EOF'

# Despachador sin lista a mano: prueba cuatro fuentes que ya existen. Un módulo
# con función <nombre>_main queda expuesto como `dcc <nombre>` sin tocar esto.

bundle_main() {
	local cmd=${1:-help} sections
	shift || true

	# 1. ¿Es una vista? -> la tabla de dashboard.sh
	if sections=$(dcc_view_sections "$cmd"); then
		[ "$cmd" = dash ] && { dashboard_main; return; }
		dashboard_main --only "$sections"; return
	fi

	# 2. Los tres que no son ni vista ni módulo ni operación.
	case "$cmd" in
		help | -h | --help | '') render_help <<<"$DCC_HELP_SRC"; return ;;
		version | -V | --version) dcc_version_info; return ;;
		dash-fast)                FAST=1 dashboard_main; return ;;
	esac

	# 3. ¿Hay un módulo que se llame así? dex -> dex_main, lang -> lang_main.
	if declare -F "${cmd//-/_}_main" >/dev/null 2>&1; then
		"${cmd//-/_}_main" "$@"; return
	fi

	# 4. ¿Es una operación? -> dispatch, que deriva de las funciones op_*
	dispatch "$cmd" "$@"
}

bundle_main "$@"
EOF
} >"$OUT.tmp"

# Aparte y luego mv (atómico): un fallo a mitad dejaría un $OUT truncado.
mv "$OUT.tmp" "$OUT"
chmod +x "$OUT"
printf '%s  (%s líneas, %s)\n' "$OUT" "$(wc -l <"$OUT")" "$(du -h "$OUT" | cut -f1)"
