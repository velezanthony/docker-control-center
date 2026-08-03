#!/usr/bin/env bash
# container-cpu.sh — CPU por contenedor desde los cgroups: NOMBRE<TAB>%, donde
# 100% es un núcleo. Sin cgroup v2 no imprime nada y el panel pinta "—".
set -uo pipefail

# 500 ms validado contra un bucle infinito: docker stats 102,21% / esto 99,8%.
INTERVAL_MS=${DCC_CPU_INTERVAL_MS:-500}
CGROUP_ROOT=${CGROUP_ROOT:-/sys/fs/cgroup}

# cgroup v2, systemd y cgroupfs en ese orden.
cpu_usec() {
	local id=$1 f
	for f in "$CGROUP_ROOT/system.slice/docker-$id.scope/cpu.stat" \
	         "$CGROUP_ROOT/docker/$id/cpu.stat"; do
		if [ -r "$f" ]; then
			awk '/^usage_usec/ { print $2; exit }' "$f" 2>/dev/null
			return 0
		fi
	done
	return 1
}

# (Δ CPU / Δ reloj) × 100. Entera: %f respetaría el locale y daría coma decimal.
pct() {
	local used=$1 elapsed=$2 d
	(( elapsed <= 0 )) && { printf '0.0%%'; return; }
	d=$(( used * 1000 / elapsed ))
	(( d < 0 )) && d=0   # un contenedor reiniciado pone su contador a cero
	printf '%d.%d%%' $(( d / 10 )) $(( d % 10 ))
}

# EPOCHREALTIME es de bash 5.0 y con `set -u` abortaría en bash 4. Se elige al
# cargar; el respaldo cuesta un fork por muestra y solo lo pagan los bash 4.
if [ -n "${EPOCHREALTIME:-}" ]; then
	now_usec() { local s=${EPOCHREALTIME/[.,]/}; printf '%s' "$s"; }
else
	now_usec() { printf '%s' "$(( $(date +%s%N) / 1000 ))"; }
fi

sample() {
	local name id u
	while IFS=$'\t' read -r name id; do
		[ -z "$id" ] && continue
		u=$(cpu_usec "$id") || continue
		[ -n "$u" ] && printf '%s\t%s\n' "$name" "$u"
	done
}

container_cpu() {
	local list t0 t1 dt
	list=$(docker ps --no-trunc --format '{{.Names}}\t{{.ID}}' 2>/dev/null) || return 1
	[ -z "$list" ] && return 0

	# =() obligatorio: sin asignar, `set -u` revienta al leer ${#first[@]}.
	declare -A first=()
	t0=$(now_usec)
	while IFS=$'\t' read -r n u; do first[$n]=$u; done < <(sample <<<"$list")

	(( ${#first[@]} == 0 )) && return 0   # cgroup v1 o sin permisos

	sleep "$(awk -v m="$INTERVAL_MS" 'BEGIN{printf "%.3f", m/1000}')"

	t1=$(now_usec); dt=$(( t1 - t0 ))
	(( dt <= 0 )) && return 0

	while IFS=$'\t' read -r n u; do
		local prev=${first[$n]:-}
		[ -z "$prev" ] && continue
		printf '%s\t%s\n' "$n" "$(pct $(( u - prev )) "$dt")"
	done < <(sample <<<"$list")
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	container_cpu "$@"
fi
