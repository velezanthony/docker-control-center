#!/usr/bin/env bash
# engine-ram.sh — RAM residente del motor, sin procps. Bash puro y no awk: mawk
# aborta al no poder abrir un fichero, y los procesos mueren mientras se leen.
set -uo pipefail

PAGE=$(getconf PAGESIZE 2>/dev/null) || PAGE=4096
[ -n "$PAGE" ] || PAGE=4096

# Entera y no %f: printf respeta el locale y escupiría "35,7".
mb() { local d=$(( $1 * PAGE * 10 / 1048576 )); printf '%d.%d' $(( d / 10 )) $(( d % 10 )); }

# "containerd" no contiene "docker", y comm trunca a 15 caracteres.
is_engine_proc() {
	case "$1" in
		*dockerd* | *containerd* | *docker-proxy*) return 0 ;;
		*) return 1 ;;
	esac
}

PROC_ROOT=${PROC_ROOT:-/proc}   # los tests apuntan a un /proc falso

engine_ram() {
	local list=${1:-0} d comm pages total=0
	for d in "$PROC_ROOT"/[0-9]*; do
		# El 2>/dev/null va ANTES del <fichero, o el error se escapa a pantalla.
		comm=""
		read -r comm 2>/dev/null <"$d/comm" || continue
		is_engine_proc "$comm" || continue
		pages=""
		read -r _ pages _ 2>/dev/null <"$d/statm" || continue
		[ -n "$pages" ] || continue
		total=$(( total + pages ))
		(( list )) && printf '%9s MB  %s\n' "$(mb "$pages")" "$comm"
	done

	if (( list )); then
		printf '%9s MB  \033[1m%s\033[0m\n' "$(mb "$total")" "TOTAL"
	else
		printf '%d' $(( total * PAGE / 1048576 ))
	fi
}

if [ -z "${DCC_BUNDLE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	# if/else y no `A && B || C`: si B fallara, C se ejecutaría también.
	if [ "${1:-}" = "--list" ]; then engine_ram 1; else engine_ram 0; fi
fi
