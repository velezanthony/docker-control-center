#!/usr/bin/env bash
# help.sh — renderiza `make help` traduciendo por nombre de target
# (`dash` -> `help_dash`); sin traducción imprime el `##` del Makefile tal cual.
# La directiva va antes de `set`, o solo afectaría a la línea siguiente.
# shellcheck disable=SC2031  # dcc_language_name carga otro catálogo aposta
set -uo pipefail

# shellcheck source=src/scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

section_key() { printf 'sec_%s' "$(printf '%s' "${1,,}" | tr ' ' '_')"; }   # `##@ Overview` -> sec_overview

# Descarta comentarios que lleven ':' y '##' en la misma línea.
is_target_name() {
	case "$1" in
		*[!a-zA-Z0-9_-]* | '') return 1 ;;
		*) return 0 ;;
	esac
}

# Lee de STDIN: el repo le pasa el Makefile y el bundle sus `##` ya extraídas.
render_help() {
	local line raw key target fallback
	printf "\n%s%s%s  %s%s%s\n%s  %s%s\n" \
		"$B" "$(t help_title)" "$R" \
		"$D" "$(t "$DCC_USAGE_KEY")" "$R" \
		"$D" "$(t "$DCC_HINT_KEY")" "$R"

	while IFS= read -r line; do
		case "$line" in
			'##@'*)
				raw=${line#\#\#@ }
				key=$(section_key "$raw")
				printf "\n%s%s%s\n" "$B" "${MSG[$key]-$raw}" "$R"
				;;
			*:*'##'*)
				target=${line%%:*}
				is_target_name "$target" || continue
				fallback=${line#*\#\# }
				printf "  %s%s%s %s\n" "$CY" "$(pad "$target" "$W_TARGET")" "$R" "${MSG[help_$target]-$fallback}"
				;;
		esac
	done

	printf "\n"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	render_help <"${1:-$DCC_ROOT/commands.txt}"
fi
