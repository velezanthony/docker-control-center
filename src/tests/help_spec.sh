# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329  # falsos positivos del DSL
#
# Tests de src/scripts/help.sh — se le da un Makefile de mentira por stdin y se
# comprueba qué pinta. Ni docker ni el Makefile real de por medio.

Describe 'section_key()'
	Include src/scripts/help.sh

	Parameters
		Overview        sec_overview
		'Operar stacks' sec_operar_stacks
		CLEANUP         sec_cleanup
	End

	It "'$1' -> $2"
		When call section_key "$1"
		The output should equal "$2"
	End
End

Describe 'render_help()'
	Include src/scripts/help.sh

	setup() {
		TMP=$(mktemp -d)
		MAKEFILE="$TMP/Makefile"
		cat >"$MAKEFILE" <<'EOF'
# un comentario cualquiera
##@ Overview
dash: ## Texto de reserva del dash
	@algo
otro-target: ## Segundo target

##@ Cleanup
clean: ## Limpia cosas
# esto NO es un target: lleva : y ## pero no es una regla
	@printf "no: soy ## un comentario\n"
EOF
	}
	cleanup() { rm -rf "$TMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	render() { render_help <"$MAKEFILE" | sed -E 's/\x1b\[[0-9;]*m//g'; }

	# grep -c SÍ imprime "0" cuando no encuentra nada, pero devuelve 1: sin el
	# `|| true` ShellSpec avisaría de un estado no afirmado en el caso vacío.
	count_targets() { render | grep -c '^  [a-z]' || true; }

	It 'agrupa por secciones y saca los targets'
		When call render
		The output should include "Overview"
		The output should include "Cleanup"
		The output should include "dash"
		The output should include "otro-target"
		The output should include "clean"
		The output should not include "soy"   # el comentario con ':' y '##' no se cuela
	End

	It 'saca exactamente 3 targets, ni uno más'
		When call count_targets
		The output should equal "3"
	End

	# La regla de qué es un comando la pone dcc_parse_commands(), en common.sh.
	# Aquí había una segunda que aceptaba mayúsculas y guiones bajos: la ayuda
	# pintaba `Foo_bar` y dispatch lo rechazaba por desconocido. Comprobado.
	It 'no pinta lo que dispatch luego rechazaría'
		strange() {
			printf '##@ Test\nFoo_bar: ## mayúscula\nmi_target: ## guión bajo\nnormal: ## este sí\n' >"$TMP/raros"
			render_help <"$TMP/raros" | sed -E 's/\x1b\[[0-9;]*m//g'
		}
		When call strange
		The output should include "normal"
		The output should not include "Foo_bar"
		The output should not include "mi_target"
	End

	It 'el catálogo gana al texto del ##, y sin clave cae al ##'
		translate() { MSG[help_dash]="TRADUCIDO desde el catálogo"; render; }
		When call translate
		The output should include "TRADUCIDO desde el catálogo"
		The output should not include "Texto de reserva del dash"
		The output should include "Segundo target"
	End

	It 'traduce también los títulos de sección'
		translate() { MSG[sec_overview]="Panorama"; render; }
		When call translate
		The output should include "Panorama"
		The output should include "Cleanup"   # la no traducida se queda en inglés
	End

	# 2 espacios de sangría + 18 de columna = la descripción empieza en la 21.
	It 'alinea la columna de targets con pad()'
		When call render
		The output should include "  otro-target        "
	End

	Describe 'con un Makefile sin targets'
		empty_makefile() {
			printf '# solo comentarios\n' >"$TMP/vacio"
			render_help <"$TMP/vacio" | sed -E 's/\x1b\[[0-9;]*m//g'
		}

		It 'sigue pintando la cabecera'
			When call empty_makefile
			The output should include "Docker Control Center"
		End

		It 'y cuenta cero targets'
			count_empty() { empty_makefile | grep -c '^  [a-z]' || true; }
			When call count_empty
			The output should equal "0"
		End
	End
End
