# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329,SC1090,SC2016
#
# Tests del empaquetado. build.sh corta los `source` casando LÍNEAS EXACTAS:
# partir en dos la de help.sh deja el repositorio en verde y el bundle ROTO.

# `slow:true` es una ETIQUETA (argumento del bloque, no una directiva `Set`), y
# `--tag` solo INCLUYE: el bucle rápido filtra por fichero. Ver `make test-fast`.
Describe 'el fichero único' slow:true
	# Construir es caro: una sola vez para todos los ejemplos.
	build() {
		BUNDLE_DIR=$(mktemp -d)
		BUNDLE="$BUNDLE_DIR/dcc"
		bash "$REPO_ROOT/build.sh" "$BUNDLE" >/dev/null 2>&1
	}
	teardown() { rm -rf "$BUNDLE_DIR"; }
	BeforeAll 'build'
	AfterAll  'teardown'

	It 'se genera, es ejecutable y es sintácticamente bash'
		is_valid() { [ -f "$BUNDLE" ] && [ -x "$BUNDLE" ] && bash -n "$BUNDLE"; }
		When call is_valid
		The status should be success
	End

	# Los `source` que quedan viven dentro de guardas que aquí no se disparan: lo
	# que importa es que no se EJECUTEN, de ahí el arranque desde /tmp.
	Describe 'NO depende de nada del disco'
		It 'no queda ningún source al disco en el nivel superior'
			loose_sources() { grep -n '^\. "' "$BUNDLE" || true; }
			When call loose_sources
			The output should be blank
		End

		# Ni indentado dentro de una guarda. La regla que los quitaba usaba `\s`,
		# que no es POSIX: mawk no lo entendía y los dejaba pasar.
		It 'tampoco queda ninguno indentado'
			indented_sources() { grep -n '\. "\$DCC_DIR/' "$BUNDLE" || true; }
			When call indented_sources
			The output should be blank
		End

		It 'arranca desde un directorio sin nada del proyecto'
			run_outside() { cd /tmp && "$BUNDLE" version 2>&1; }
			When call run_outside
			The output should include "Docker Control Center"
			The output should not include "No existe el archivo"
			The output should not include "orden no encontrada"
		End
	End

	Describe 'lleva dentro lo que en el repositorio son ficheros'
		Parameters
			"_catalog_es()" "los catálogos, como funciones"
			"_catalog_en()" ""
			"JQ_METRICS="   "los programas jq, como variables"
			"DCC_HELP_SRC=" "las líneas ## de la ayuda"
		End

		It "$1 $2"
			read_bundle() { printf '%s' "$(<"$BUNDLE")"; }
			When call read_bundle
			The output should include "$1"
		End
	End

	# Se CARGA y se le preguntan sus funciones: ejecutar cada comando colgaba la
	# suite, porque `stats` transmite hasta que lo matas.
	It 'expone exactamente las mismas operaciones que el repositorio'
		same_ops() {
			local repo bundle
			repo=$(cd "$REPO_ROOT" && bash -c '. src/scripts/ops.sh; dispatch_names')
			bundle=$(. "$BUNDLE" help >/dev/null 2>&1; dispatch_names)
			[ "$repo" = "$bundle" ]
		}
		When call same_ops
		The status should be success
	End

	Describe 'define lo que la interfaz necesita'
		Parameters
			dashboard_main
			dex_main
			lang_main
			render_help
			dcc_version_info
			dispatch
		End

		It "define $1"
			When run bash -c '. "$1" help >/dev/null 2>&1; declare -F "$2" >/dev/null' _ "$BUNDLE" "$1"
			The status should be success
		End
	End

	# BUNDLE_ORDER manda sobre el ORDEN, no sobre la pertenencia: añadir un script
	# a src/scripts/ no debe obligar a tocar build.sh. Se mete uno de mentira, se
	# reconstruye y se comprueba que entró Y que quedó despachado.
	It 'un script nuevo entra en el bundle sin tocar build.sh'
		auto_discovery() {
			local tmp="$REPO_ROOT/src/scripts/zz-probe.sh" out
			# La guarda va en la forma CANÓNICA de tres líneas: strip_module casa
			# líneas exactas, y con la variante de una línea sobrevive al
			# empaquetado y el módulo se ejecuta al cargarse.
			cat >"$tmp" <<-'PROBE'
				#!/usr/bin/env bash
				zz_probe_main() { printf 'sonda-ok\n'; }
				if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
					zz_probe_main "$@"
				fi
			PROBE
			out=$(mktemp -d)/dcc
			bash "$REPO_ROOT/build.sh" "$out" >/dev/null 2>&1
			rm -f "$tmp"
			grep -q 'zz_probe_main' "$out" || return 1
			(cd /tmp && "$out" zz-probe)
		}
		When call auto_discovery
		The output should equal "sonda-ok"
	End

	# El reverso: un módulo inexistente tiene que ABORTAR. Dentro de `< <(...)` el
	# `exit 1` moría en la subshell y se escribía un bundle de 2 módulos con rc 0.
	It 'aborta sin escribir nada si BUNDLE_ORDER nombra un módulo que no existe'
		bogus_module() {
			local probe="$REPO_ROOT/zz-build-probe.sh" out status
			sed 's/^BUNDLE_ORDER=(/BUNDLE_ORDER=(\n\tzz-no-existe/' "$REPO_ROOT/build.sh" >"$probe"
			out=$(mktemp -d)/dcc
			bash "$probe" "$out" >/dev/null 2>&1
			status=$?
			rm -f "$probe"
			[ "$status" -ne 0 ] && [ ! -e "$out" ]
		}
		When call bogus_module
		The status should be success
	End

	It 'las 6 vistas están en la tabla'
		missing_views() {
			local missing=""
			for v in dash status ps psa images volumes; do
				(. "$BUNDLE" help >/dev/null 2>&1; dcc_view_sections "$v") >/dev/null 2>&1 || missing+=" $v"
			done
			printf '%s' "$missing"
		}
		When call missing_views
		The output should be blank
	End

	It 'se anuncia como dcc, no como make'
		help_output() { cd /tmp && "$BUNDLE" help 2>&1; }
		When call help_output
		The output should include "dcc <"
		The output should not include "S=stack"
	End

	# `dcc help` llegó a prometer lint, test, bundle y check, que el bundle no tiene.
	Describe 'la ayuda no anuncia lo que no tiene'
		Parameters
			"  lint "
			"  check "
			"  test "
			"  bundle "
			"Development"
		End

		It "no anuncia '$1'"
			help_output() { cd /tmp && "$BUNDLE" help 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g'; }
			When call help_output
			The output should not include "$1"
		End
	End

	# Y al revés: lo que sí anuncia tiene que existir. 2 = operación desconocida.
	It 'todo lo que anuncia existe de verdad'
		broken_commands() {
			local help_text broken=""
			help_text=$(cd /tmp && "$BUNDLE" help 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g')
			while read -r c; do
				# Se saltan los que abren menú, esperan entrada o transmiten sin parar.
				case "$c" in
					stats|tail|sh|logs|dex|kill-all|clean*|volume-*|stack-*|rm-image|inspect|start|stop|restart) continue ;;
				esac
				(cd /tmp && "$BUNDLE" "$c" >/dev/null 2>&1)
				[ $? -eq 2 ] && broken+=" $c"
			done < <(printf '%s\n' "$help_text" | grep -oE '^  [a-z][a-z-]*' | tr -d ' ')
			printf '%s' "$broken"
		}
		When call broken_commands
		The output should be blank
	End
End

# Miran el CÓDIGO FUENTE, no el bundle: que funcione en una máquina ajena.
Describe 'el código fuente no se sale de los requisitos'

	# ops.sh usaba `sd` y sin él la lista no se imprimía, en silencio. Se quitan
	# los comentarios antes de mirar: pueden nombrar la herramienta descartada.
	It 'no usa rg, sd, fd, bat, eza ni delta'
		intruder_tools() {
			local code found=""
			code=$(cat "$REPO_ROOT"/src/scripts/*.sh "$REPO_ROOT"/src/tests/*.sh \
			           "$REPO_ROOT/Makefile" "$REPO_ROOT/build.sh" "$REPO_ROOT/deps.sh" \
			           2>/dev/null | sed 's/#.*//')
			for t in rg sd fd bat eza delta; do
				printf '%s' "$code" | grep -qE "(^|[|(;&\\] *)$t +[-'\"]" && found+=" $t"
			done
			printf '%s' "$found"
		}
		When call intruder_tools
		The output should be blank
	End

	# El README promete bash 4+, y EPOCHREALTIME (bash 5.0) abortaba el script.
	It 'no usa construcciones posteriores a bash 4.0 sin guardar'
		modern_constructs() {
			local code found=""
			code=$(cat "$REPO_ROOT"/src/scripts/*.sh | sed 's/#.*//')
			for c in 'wait -n' 'local -n' 'BASH_ARGV0' '@Q}' '@U}' '@a}'; do
				printf '%s' "$code" | grep -qF "$c" && found+=" $c"
			done
			printf '%s' "$found"
		}
		When call modern_constructs
		The output should be blank
	End

	It 'quien usa EPOCHREALTIME comprueba antes y trae respaldo para bash 4'
		has_fallback() {
			local f
			for f in "$REPO_ROOT"/src/scripts/*.sh; do
				grep -q 'EPOCHREALTIME' "$f" || continue
				grep -q 'if \[ -n "${EPOCHREALTIME:-}" \]' "$f" || return 1
				grep -q 'date +%s%N' "$f" || return 1
			done
		}
		When call has_fallback
		The status should be success
	End
End
