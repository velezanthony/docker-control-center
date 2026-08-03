# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317,SC2329
# shellcheck disable=SC2154  # $SEP lo define common.sh, que carga el spec
#
# fixtures.sh — host de mentira de la suite. Todo INVENTADO: un test debe dar lo
# mismo en cualquier máquina y su salida acaba en un issue público.
#   demo_web-1 (stack demo) · demo_db-1 (parado) · otro_web-1 (otro) · suelto-1

fixture_running_names() { printf '%s\n' demo_web-1 otro_web-1 suelto-1; }
fixture_all_names()     { printf '%s\n' demo_web-1 demo_db-1 otro_web-1 suelto-1; }

# Formato de dex.sh: nombre SEP proyecto SEP servicio. $SEP se queda AQUÍ dentro:
# cruzando un `When` aborta la suite con código 102.
fixture_ps_rows() {
	printf '%s\n' \
		"demo_web-1${SEP}demo${SEP}web" \
		"otro_web-1${SEP}otro${SEP}web" \
		"suelto-1${SEP}${SEP}"
}

FIXTURE_DOCKER_LOG=/dev/null   # global: un `local` moriría antes de llamar a docker()

fixture_dex_docker() {
	FIXTURE_DOCKER_LOG=$1
	docker() {
		printf 'docker %s\n' "$*" >>"$FIXTURE_DOCKER_LOG"
		case "$*" in
			*--filter*) printf '%s\n' "demo${SEP}web" ;;   # print_best
			*Label*)    fixture_ps_rows ;;                  # print_available
			"ps --format {{.Names}}") fixture_running_names ;;
		esac
		return 0
	}
}
