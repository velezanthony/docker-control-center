#!/usr/bin/env bash
# dex.sh — `docker exec <contenedor> [comando]` a prueba de dedos: sin comando
# abre una shell, y si el nombre no casa sugiere el más parecido y sale != 0.
set -uo pipefail

# shellcheck source=src/scripts/common.sh
declare -F pad >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

err() { printf "%s\n" "$*" >&2; }

# Ordenado: best_match recorre la lista y un empate debe resolverse igual siempre.
running() { dcc_names | sort; }

# Agrupados por stack; los sueltos, aparte. A stderr: acompaña a un error.
print_available() {
	local rows
	rows=$(docker ps --format "{{.Names}}$SEP{{.Label \"com.docker.compose.project\"}}$SEP{{.Label \"com.docker.compose.service\"}}" \
		| sort -t"$SEP" -k2,2 -k1,1)
	if [ -z "$rows" ]; then
		err "${YE}$(t dex_none_running)${R}"
		err "${D}$(t dex_hint_up)${R}"
		return
	fi

	# Pre-pass: ancho máximo del nombre (para alinear) y nº por stack.
	local w=0 name proj svc key
	declare -A count
	while IFS="$SEP" read -r name proj svc; do
		(( ${#name} > w )) && w=${#name}
		key=${proj:-·sin·stack·}
		count[$key]=$(( ${count[$key]:-0} + 1 ))
	done <<< "$rows"

	err ""
	err "  ${B}$(t dex_available)${R}"
	local cur="" n plural
	while IFS="$SEP" read -r name proj svc; do
		key=${proj:-·sin·stack·}
		if [ "$key" != "$cur" ]; then
			cur=$key
			n=${count[$key]}
			plural=$(t dex_services); (( n == 1 )) && plural=$(t dex_service)
			err ""
			if [ -n "$proj" ]; then
				err "  ${CY}${B}▸ ${proj}${R}  ${D}(${n} ${plural})${R}"
			else
				err "  ${D}${B}▸ $(t dex_no_stack)${R}  ${D}(${n} ${plural})${R}"
			fi
		fi
		# pad() y no "%-*s": printf rellena por BYTES y los acentos descuadran.
		printf "    ${GR}●${R} ${B}%s${R}  ${D}%s${R}\n" "$(pad "$name" "$w")" "${svc:-—}" >&2
	done <<< "$rows"
	err ""
}

# El más parecido, con su servicio y stack para ver de dónde sale.
print_best() {
	local cand=$1 meta proj svc
	meta=$(docker ps --filter "name=^${cand}$" \
		--format "{{.Label \"com.docker.compose.project\"}}$SEP{{.Label \"com.docker.compose.service\"}}")
	IFS="$SEP" read -r proj svc <<< "$meta"
	err ""
	err "  ${B}$(t dex_closest)${R}"
	err ""
	printf "    ${GR}●${R} ${B}%s${R}  ${D}%s${R}\n" "$cand" "${svc:-—}" >&2
	if [ -n "$proj" ]; then
		err "      ${D}$(t dex_stack) ${CY}${proj}${R}"
	else
		err "      ${D}$(t dex_no_stack)${R}"
	fi
}

# Fuzzy sin dependencias. Compose prefija con el proyecto (demo_web-1), así que
# comparar desde el inicio no sirve: se deslizan ventanas y gana la coincidencia
# más larga. Devuelve "candidato<TAB>puntuación", o nada si no llega a 3 chars.
best_match() {
	local target=$1 cand best="" best_score=0 t_lc c_lc tn score hit len i
	t_lc=${target,,}; tn=${#t_lc}
	while IFS= read -r cand; do
		[ -z "$cand" ] && continue
		c_lc=${cand,,}
		score=0
		for ((len = tn; len >= 3; len--)); do
			hit=0
			for ((i = 0; i + len <= tn; i++)); do
				if [[ "$c_lc" == *"${t_lc:i:len}"* ]]; then hit=$len; break; fi
			done
			if (( hit > 0 )); then score=$hit; break; fi
		done
		if (( score > best_score )); then best_score=$score; best=$cand; fi
	done
	(( best_score >= 3 )) && printf '%s\t%s' "$best" "$best_score"
	return 0
}

dex_main() {
target=${1:-}
if [ -z "$target" ]; then
	err "${RD}$(t dex_missing_name)${R}"
	err "${D}$(t dex_usage)${R}"
	print_available
	exit 2
fi
shift  # lo que quede en "$@" es el comando

list=$(running)
if ! grep -qxF "$target" <<< "$list"; then
	err "${RD}$(tf dex_not_found "${B}${target}${R}${RD}")${R}"

	if [ -z "$list" ]; then
		err "${YE}$(t dex_none_at_all)${R}"
		exit 1
	fi

	best=$(best_match "$target" <<<"$list" | cut -f1)
	[ -n "$best" ] && print_best "$best"
	print_available
	exit 1
fi

# Sin comando, shell; con comando, ese comando. Los flags y la elección de
# bash/sh viven en dcc_exec(), que comparte con `dcc sh`.
[ "$#" -eq 0 ] && printf "%s\n" "${D}$(tf dex_opening "${CY}${target}${R}${D}")${R}" >&2
dcc_exec "$target" "$@"
}

# Define al cargarse; ejecuta solo si lo lanzas directo.
if [ -z "${DCC_BUNDLE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	dex_main "$@"
fi
