#!/usr/bin/env bash
# bundle-main.sh — el despachador del FICHERO ÚNICO, y SIEMPRE lo último que
# build.sh concatena: cuando corre, todo lo que llama ya está definido.
#
# Su guarda es la INVERSA que la de los demás módulos: esto solo tiene sentido
# con DCC_BUNDLE puesto. En el repositorio se carga, define, y calla.
#
# La directiva va antes de `set`, o solo afectaría a la línea siguiente.
# shellcheck disable=SC2154  # DCC_HELP_SRC lo incrusta build.sh dentro del bundle
set -uo pipefail

# Sin lista a mano: prueba cuatro fuentes que ya existen. Un módulo con función
# <nombre>_main queda expuesto como `dcc <nombre>` sin tocar este fichero.
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

	# 4. ¿Es una operación? -> dispatch: commands.txt ∩ funciones op_*
	dispatch "$cmd" "$@"
}

[ -n "${DCC_BUNDLE:-}" ] && bundle_main "$@"
