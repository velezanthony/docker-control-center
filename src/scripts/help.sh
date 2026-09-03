#!/usr/bin/env bash
# help.sh — renderiza la ayuda traduciendo por nombre (`dash` -> `help_dash`);
# sin traducción imprime el `##` de la entrada tal cual. Sirve a las dos: el
# Makefile en el repositorio y src/commands.txt en el fichero único.
# La directiva va antes de `set`, o solo afectaría a la línea siguiente.
# shellcheck disable=SC2031  # dcc_language_name carga otro catálogo aposta
set -uo pipefail

# shellcheck source=src/scripts/common.sh
declare -F pad >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

section_key() { printf 'sec_%s' "$(printf '%s' "${1,,}" | tr ' ' '_')"; }   # `##@ Overview` -> sec_overview

# Lee de STDIN: el repo le pasa el Makefile y el bundle sus `##` ya extraídas.
# Qué línea cuenta NO se decide aquí, sino en dcc_parse_commands() (common.sh).
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
			*)
				target=${line%%:*}
				fallback=${line#*\#\# }
				printf "  %s%s%s %s\n" "$CY" "$(pad "$target" "$W_TARGET")" "$R" "${MSG[help_$target]-$fallback}"
				;;
		esac
	done < <(dcc_parse_commands lines)

	printf "\n"
}

if [ -z "${DCC_BUNDLE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	render_help <"${1:-$DCC_ROOT/commands.txt}"
fi
