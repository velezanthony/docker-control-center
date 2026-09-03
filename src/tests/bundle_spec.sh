# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329,SC1090,SC2016
#
# Aquí el bundle se lanza como PROCESO, así que el cerrojo de spec_helper.sh no
# llega: `docker()` es una función de bash y no cruza a un hijo. De ahí el docker
# falso al frente del PATH — sin él, cada máquina daba un resultado distinto.

# `slow:true` es una ETIQUETA (argumento del bloque, no una directiva `Set`), y
# `--tag` solo INCLUYE: el bucle rápido filtra por fichero. Ver `make test-fast`.
Describe 'el fichero único' slow:true
	# Construir es caro: una sola vez para todos los ejemplos.
	build() {
		BUNDLE_DIR=$(mktemp -d)
		BUNDLE="$BUNDLE_DIR/dcc"
		bash "$REPO_ROOT/build.sh" "$BUNDLE" >/dev/null 2>&1

		# Mudos: aquí se comprueba el DESPACHO, no qué contesta docker. Fingir
		# datos sería una segunda implementación; los render van en dashboard_spec.
		FAKE_BIN="$BUNDLE_DIR/bin"; mkdir -p "$FAKE_BIN"
		local c
		for c in docker systemctl curl; do
			printf '#!/bin/sh\nexit 0\n' >"$FAKE_BIN/$c"
			chmod +x "$FAKE_BIN/$c"
		done
		ORIG_PATH=$PATH
		PATH="$FAKE_BIN:$PATH"; export PATH
	}
	teardown() { PATH=$ORIG_PATH; rm -rf "$BUNDLE_DIR"; }
	BeforeAll 'build'
	AfterAll  'teardown'

	# Si el falso dejara de interceptar, todo lo de abajo volvería a hablar con el
	# docker de la máquina y nadie se enteraría: seguiría en verde.
	It 'el docker falso intercepta de verdad'
		resolved() { bash -c 'command -v docker'; }
		When call resolved
		The output should equal "$FAKE_BIN/docker"
	End

	It 'se genera, es ejecutable y es sintácticamente bash'
		is_valid() { [ -f "$BUNDLE" ] && [ -x "$BUNDLE" ] && bash -n "$BUNDLE"; }
		When call is_valid
		The status should be success
	End

	Describe 'NO depende de nada del disco'
		# Ficheros trampa con el nombre de los hermanos: si un `source` se disparara
		# o una guarda se creyera la principal, gritarían. Prueba la PROPIEDAD —del
		# disco no se carga nada— y no si build.sh supo reconocer una línea.
		It 'no carga ningún hermano aunque estén ahí al lado'
			decoys() {
				local d f; d=$(mktemp -d); cp "$BUNDLE" "$d/dcc"
				for f in common.sh engine-ram.sh container-cpu.sh; do
					printf 'printf "BOOM %s\\n" >&2\n' "$f" >"$d/$f"
				done
				( cd "$d" && ./dcc version >/dev/null && ./dcc help >/dev/null ) 2>&1
				rm -rf "$d"
			}
			When call decoys
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
			# La guarda va en UNA línea A PROPÓSITO: el empaquetado ya no depende de
			# cómo esté escrita, y este ejemplo es lo que lo demuestra.
			cat >"$tmp" <<-'PROBE'
				#!/usr/bin/env bash
				zz_probe_main() { printf 'sonda-ok\n'; }
				[ -z "${DCC_BUNDLE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ] && zz_probe_main "$@"
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

	# bundle_main() vivía en un heredoc de build.sh, donde shellcheck no entra.
	# Ahora es src/scripts/bundle-main.sh y build.sh lo pega el ÚLTIMO a mano: si
	# entrara por el descubrimiento automático, un `zz-*.sh` nuevo caería detrás y
	# el despachador correría antes de que ese módulo existiera.
	Describe 'el despachador'
		It 'es lo último del fichero, después de todos los módulos'
			last_definition() {
				grep -n '^# --- ' "$BUNDLE" | tail -1 | sed 's/.*--- //; s/ .*//'
			}
			When call last_definition
			The output should equal "bundle-main.sh"
		End

		It 'y su llamada es la última línea de todo'
			last_line() { tail -1 "$BUNDLE"; }
			When call last_line
			The output should include "bundle_main"
		End
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
			# Misma clase de caracteres que dcc_parse_commands(): con `[a-z-]*` un
			# comando con dígito (ps2) se saltaba en silencio y no se comprobaba.
			done < <(printf '%s\n' "$help_text" | grep -oE '^  [a-z][a-z0-9-]*' | tr -d ' ')
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
