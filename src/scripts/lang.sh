#!/usr/bin/env bash
# lang.sh — ver y cambiar el idioma: sin argumento menú, `en` lo fija, `auto` lo
# redetecta. Escribe en .config porque un hijo no puede cambiar el entorno de su padre.
set -uo pipefail

# Antes del source: hace falta para avisar de que un DCC_LANG exportado seguirá
# ganándole al .config.
ENV_LANG=${DCC_LANG:-}
# shellcheck source=src/scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Los da common.sh: la fuente cambia entre repositorio y bundle.
codes()   { dcc_languages; }
name_of() { dcc_language_name "$1"; }

# Nada de `codes | grep -q`: grep sale al acertar, codes muere con SIGPIPE y
# pipefail lo propaga — la comprobación fallaba justo al encontrarlo.
known() { local c; while read -r c; do [ "$c" = "$1" ] && return 0; done < <(codes); return 1; }

# Reescribe solo la clave DCC_LANG y conserva el resto del fichero.
# $1 = valor, o vacío para borrar la preferencia.
write_cfg() {
	local val=${1:-} dir tmp line
	dir=$(dirname "$DCC_CONFIG")
	# Si existe y NO es un fichero normal, fuera: el mv de abajo reemplazaría un
	# nodo de dispositivo. Con DCC_CONFIG=/dev/null y suficientes permisos, esto
	# se cargaría /dev/null. El `cp` de antes no tenía ese riesgo.
	if [ -e "$DCC_CONFIG" ] && [ ! -f "$DCC_CONFIG" ]; then return 1; fi
	# Puede no existir: es la primera vez que se guarda una preferencia.
	mkdir -p "$dir" 2>/dev/null || return 1

	# El temporal va EN EL MISMO directorio que el destino para que el mv de
	# abajo sea atómico: entre sistemas de ficheros, mv degrada a copiar y
	# borrar, y un lector podría ver el fichero a medias.
	tmp=$(mktemp "$dir/.config.XXXXXX" 2>/dev/null) || return 1

	# Un solo camino de éxito y una sola limpieza. Nada de `trap … RETURN`: $tmp
	# es local y ya ha muerto cuando el trap se ejecuta, así que con `set -u`
	# aborta la función.
	#
	# El estado del `mv` es el de la función. Antes acababa en
	# `cp …; rm -f "$tmp"`, o sea que devolvía el del rm —siempre 0— y apply()
	# pintaba "✓ Guardado en …" con la escritura fallada.
	{
		if [ -r "$DCC_CONFIG" ]; then
			while IFS= read -r line || [ -n "$line" ]; do
				case "${line//[[:space:]]/}" in DCC_LANG=*) continue ;; esac
				printf '%s\n' "$line"
			done <"$DCC_CONFIG"
		else
			printf '# %s\n' "$(t cfg_header)"
		fi
		[ -n "$val" ] && printf 'DCC_LANG=%s\n' "$val"
		:
	} >"$tmp" && mv "$tmp" "$DCC_CONFIG" && return 0

	rm -f "$tmp"
	return 1
}

origin_text() {
	case "$DCC_LANG_ORIGIN" in
		env)    t lang_from_env ;;
		config) tf lang_from_config "$DCC_CONFIG" ;;
		locale) t lang_from_locale ;;
		*)      t lang_from_default ;;
	esac
}

show_current() {
	printf "\n  "
	tf lang_current "${B}$DCC_LANG_RESOLVED${R} ${D}$(name_of "$DCC_LANG_RESOLVED")${R}" "${D}$(origin_text)${R}"
	printf "\n"
	# Aquí es donde el usuario viene a entender por qué ve lo que ve.
	if [ -n "$ENV_LANG" ] && _dcc_cfg_get DCC_LANG >/dev/null 2>&1; then
		warn_env_blocks
	fi
}

# Con DCC_LANG exportado el entorno gana al fichero: el comando no ha servido de
# nada, así que va en rojo, con el arreglo, y sin el ✓.
warn_env_blocks() {
	[ -n "$ENV_LANG" ] || return 0
	printf "\n  ${RD}⚠ %s${R}\n" "$(t lang_env_blocks)"
	printf "  %s\n" "$(t lang_env_fix)"
	# shellcheck disable=SC2059  # el color va en el formato, como en todo el proyecto
	printf "      ${CY}unset DCC_LANG${R}\n"
}

# `unset` y no `DCC_LANG="" …`: en un builtin el prefijo PERSISTE.
# Si el guardado falla NO se pinta el ✓ y se sale con != 0: decirle a alguien
# "Guardado en X" cuando X no se ha escrito es peor que no decir nada.
apply() {
	local want=$1 mark="${GR}✓${R}"
	[ -n "$ENV_LANG" ] && mark="${YE}•${R}"
	if [ "$want" = auto ]; then
		write_cfg "" || { warn_save_failed; return 1; }
		unset DCC_LANG; dcc_load_language
		printf "\n  %b %s\n" "$mark" "$(t lang_unset_ok)"
	else
		write_cfg "$want" || { warn_save_failed; return 1; }
		unset DCC_LANG; dcc_load_language
		printf "\n  %b %s\n" "$mark" "$(tf lang_set_ok "${B}$(name_of "$want")${R}")"
		printf "  ${D}%s${R}\n" "$(tf lang_set_where "$DCC_CONFIG")"
	fi
	warn_env_blocks
	printf "\n"
}

warn_save_failed() {
	printf "\n  ${RD}%s${R}\n\n" "$(tf lang_save_failed "$DCC_CONFIG")" >&2
}

lang_main() {
arg=${1:-}
if [ -n "$arg" ]; then
	case "$arg" in
		auto | reset | unset) apply auto; exit 0 ;;
	esac
	if known "$arg"; then apply "$arg"; exit 0; fi
	printf "\n  ${RD}%s${R}\n" "$(tf lang_set_unknown "$arg")"
	printf "  %s %s\n\n" "$(t lang_available)" "$(codes | join_list)"
	exit 1
fi

show_current

# Sin TTY un menú se cuelga o sale en vacío: se lista y punto.
if [ ! -t 0 ] || [ ! -t 1 ]; then
	printf "\n  %s\n" "$(t lang_available)"
	while read -r c; do printf "    ${CY}%s lang %s${R}  ${D}%s${R}\n" "$DCC_CMD" "$c" "$(name_of "$c")"; done < <(codes)
	printf "    ${CY}%s lang auto${R}  ${D}%s${R}\n\n" "$DCC_CMD" "$(t lang_auto_desc)"
	exit 0
fi

printf "\n  ${B}%s${R}\n" "$(t lang_menu_prompt)"

opts=()
while read -r c; do opts+=("$c — $(name_of "$c")"); done < <(codes)
opts+=("auto — $(t lang_auto_desc)")

PS3=$'\n> '
select choice in "${opts[@]}"; do
	[ -n "${choice:-}" ] || continue
	apply "${choice%% *}"
	break
done
}

# Define al cargarse; ejecuta solo si lo lanzas directo.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	lang_main "$@"
fi
