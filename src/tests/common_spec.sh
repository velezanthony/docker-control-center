# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329  # falsos positivos del DSL
#
# Tests de src/scripts/common.sh — funciones puras, cero docker.

Describe 'pad()'
	Include src/scripts/common.sh

	# El bug: printf "%-10s" rellena por BYTES, así que "café" (5 bytes, 4 chars)
	# se quedaba una columna corta y descuadraba la tabla entera.
	Parameters
		"web"             6 "web   "   ""
		"café"            6 "café  "   "bytes != chars"
		"señor"           6 "señor "   "ñ cuenta como UN carácter"
		"demasiado-largo" 8 "demasia…" "trunca a 8 CONTANDO el …, no a 9"
		""                3 "   "      "cadena vacía = solo relleno"
	End

	It "cuenta caracteres, no bytes: '$1' $4"
		When call pad "$1" "$2"
		The output should equal "$3"
	End
End

Describe 'rpad()'
	Include src/scripts/common.sh

	It 'alinea el número a la derecha'
		When call rpad "42" 5
		The output should equal "   42"
	End

	It 'si no cabe NO trunca: no miente con números'
		When call rpad "12345" 3
		The output should equal "12345"
	End
End

# Con IFS=TAB bash colapsa los separadores seguidos y todo se corre un puesto.
# Es EXACTAMENTE el bug que hacía que un contenedor sin puertos perdiera el
# nombre de servicio y mostrara el proyecto en la columna de imagen.
#
# OJO: $SEP es \x1f y NO puede viajar por los argumentos de `When` — choca con el
# protocolo de reporte de ShellSpec y aborta la suite con código 102 aunque los
# tests pasen. Por eso cada caso arma su cadena DENTRO de la función.
Describe 'SEP'
	Include src/scripts/common.sh

	It 'un campo vacío en medio NO desplaza los siguientes'
		read_four() {
			local a b c d
			IFS="$SEP" read -r a b c d <<<"uno${SEP}dos${SEP}${SEP}cuatro"
			printf '%s|%s|%s|%s' "$a" "$b" "$c" "$d"
		}
		When call read_four
		The output should equal "uno|dos||cuatro"
	End

	It 'tres vacíos seguidos siguen siendo tres campos'
		read_four() {
			local a b c d
			IFS="$SEP" read -r a b c d <<<"uno${SEP}${SEP}${SEP}cuatro"
			printf '%s|%s|%s|%s' "$a" "$b" "$c" "$d"
		}
		When call read_four
		The output should equal "uno|||cuatro"
	End

	# Se documenta el fallo para que nadie lo "simplifique" volviendo a TAB.
	It 'con TAB el campo vacío se come y cuatro sube de puesto'
		read_four_tab() {
			local a b c d
			IFS=$'\t' read -r a b c d <<<$'uno\tdos\t\tcuatro'
			printf '%s|%s|%s|%s' "$a" "$b" "$c" "$d"
		}
		When call read_four_tab
		The output should equal "uno|dos|cuatro|"
	End
End

Describe '_dcc_cfg_get()'
	Include src/scripts/common.sh

	setup()   { TMP=$(mktemp -d); DCC_CONFIG="$TMP/.config"; }
	cleanup() { rm -rf "$TMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	It 'lee una clave simple'
		printf 'DCC_LANG=es\n' >"$DCC_CONFIG"
		When call _dcc_cfg_get DCC_LANG
		The output should equal "es"
	End

	It 'ignora comentarios y espacios alrededor'
		printf '# un comentario\n  DCC_LANG = en   \n' >"$DCC_CONFIG"
		When call _dcc_cfg_get DCC_LANG
		The output should equal "en"
	End

	It 'quita las comillas dobles'
		printf 'DCC_LANG="es"\n' >"$DCC_CONFIG"
		When call _dcc_cfg_get DCC_LANG
		The output should equal "es"
	End

	It 'quita las comillas simples'
		printf "DCC_LANG='es'\n" >"$DCC_CONFIG"
		When call _dcc_cfg_get DCC_LANG
		The output should equal "es"
	End

	It 'una clave ausente devuelve != 0'
		printf 'OTRA=cosa\n' >"$DCC_CONFIG"
		When call _dcc_cfg_get DCC_LANG
		The status should be failure
		The output should be blank
	End

	It 'una clave con valor vacío devuelve != 0'
		printf 'DCC_LANG=\n' >"$DCC_CONFIG"
		When call _dcc_cfg_get DCC_LANG
		The status should be failure
		The output should be blank
	End

	# Se parsea, NO se hace source: un .config es un fichero del usuario.
	It 'un .config con código no lo ejecuta'
		printf 'DCC_LANG=es\nrm -rf /tmp/deberia-no-existir-jamas\n' >"$DCC_CONFIG"
		When call _dcc_cfg_get DCC_LANG
		The output should equal "es"
	End

	It 'un fichero inexistente devuelve != 0'
		DCC_CONFIG="$TMP/no-existe"
		When call _dcc_cfg_get DCC_LANG
		The status should be failure
		The output should be blank
	End
End

Describe 't() / tf() / say()'
	Include src/scripts/common.sh

	It 'devuelve el mensaje literal'
		set_msg() { MSG[_test_plain]="hola"; t _test_plain; }
		When call set_msg
		The output should equal "hola"
	End

	It 'aplica el formato con tf()'
		set_msg() { MSG[_test_fmt]="tienes %s mensajes"; tf _test_fmt 3; }
		When call set_msg
		The output should equal "tienes 3 mensajes"
	End

	# Devuelve su nombre en vez de reventar: se ve qué clave falta.
	It 'una clave que no existe devuelve su propio nombre'
		When call t _clave_que_no_existe
		The output should equal "_clave_que_no_existe"
	End

	It 'say() añade el salto de línea'
		set_msg() { MSG[_test_plain]="hola"; say _test_plain; }
		When call set_msg
		The output should equal "hola"
	End
End

# En el repositorio los catálogos son ficheros de i18n/; en el fichero único son
# funciones _catalog_*. Quien pregunta no debe enterarse de la diferencia.
Describe 'dcc_languages()'
	Include src/scripts/common.sh

	# _catalog_en es el CENTINELA que usa dcc_languages para saber si los
	# catálogos están incrustados. Con solo _catalog_zz seguiría leyendo los
	# ficheros del repositorio, que es lo correcto.
	embed_catalogs() {
		_catalog_en() { MSG+=([lang_name]="English"); }
		_catalog_zz() { MSG+=([lang_name]="Zzz"); }
	}

	It 'los lista desde los ficheros de i18n/ del repositorio'
		list_langs() { dcc_languages | tr '\n' ' '; }
		When call list_langs
		The output should equal "en es "
	End

	It 'con los catálogos incrustados, los lista de ahí'
		list_langs() { embed_catalogs; dcc_languages | tr '\n' ' '; }
		When call list_langs
		The output should include "zz"
		The output should include "en"
	End

	It 'el nombre sale del propio catálogo incrustado'
		catalog_name() { embed_catalogs; dcc_language_name zz; }
		When call catalog_name
		The output should equal "Zzz"
	End
End

Describe 'dcc_language_name()'
	Include src/scripts/common.sh

	# Carga OTRO catálogo para leer su nombre. Si no lo aislara en una subshell,
	# la interfaz saldría con idiomas mezclados a partir de ahí.
	It 'NO contamina el idioma activo al preguntar por otro'
		isolated() {
			_catalog_en() { MSG+=([lang_name]="English"); }
			_catalog_zz() { MSG+=([lang_name]="Zzz"); }
			local before; before=$(t help_title)
			dcc_language_name zz >/dev/null
			[ "$(t help_title)" = "$before" ]
		}
		When call isolated
		The status should be success
	End

	It 'un idioma que no existe devuelve vacío, no revienta'
		When call dcc_language_name inventado
		The output should be blank
		The status should be failure
	End
End

Describe 'dcc_load_language()'
	Include src/scripts/common.sh

	# lang.sh la llama otra vez tras guardar la preferencia. Si MSG fuera local a
	# la función, el catálogo nuevo moriría al volver y saldría el idioma viejo.
	It 'se puede repetir: cambia a español y vuelve a inglés'
		round_trip() {
			DCC_LANG=es dcc_load_language
			printf '%s|%s|' "$DCC_LANG_RESOLVED" "$(t help_help)"
			DCC_LANG=en dcc_load_language
			printf '%s|%s' "$DCC_LANG_RESOLVED" "$(t help_help)"
		}
		When call round_trip
		The output should include "es|"
		The output should include "Muestra"
		The output should include "en|"
		The output should include "Show"
	End

	It 'sabe que el idioma vino del entorno'
		origin_of() { DCC_LANG=es dcc_load_language; printf '%s' "$DCC_LANG_ORIGIN"; }
		When call origin_of
		The output should equal "env"
	End

	# Aquí solo hace falta el VALOR de la variable: dcc_load_language casa el
	# patrón de la cadena, no cambia el locale del proceso. Pero el prefijo
	# `LC_ALL=… cmd` SÍ intenta aplicarlo, y bash avisa por stderr si no está
	# generado — en un contenedor limpio eso tumbaba el ejemplo. Se asigna dentro
	# de la función, donde no hay setlocale de por medio.
	It 'sabe que el idioma vino del locale'
		origin_of() {
			unset DCC_LANG
			( LC_ALL=es_ES.UTF-8; dcc_load_language; printf '%s' "$DCC_LANG_ORIGIN" ) 2>/dev/null
		}
		When call origin_of
		The output should equal "locale"
	End
End

# Lo primero que se le pide a quien reporta un fallo. Una sola implementación
# para `make version` y para el fichero único: antes eran dos copias.
# Los catálogos se cargan con `source`, así que unas comillas invertidas o un
# $( ) no son texto: son EJECUCIÓN. Pasó con [help_link]="… `dcc` …", que
# intentaba ejecutar dcc al cargar el catálogo y reventaba `make run` entero.
# ${DCC_CMD} sí vale: es expansión de parámetro, no de comando.
Describe 'los catálogos son datos, no código'
	It 'ninguno ejecuta comandos al cargarse'
		command_substitution() {
			grep -nE '`|\$\(' "$REPO_ROOT"/src/i18n/*.sh | sed 's|.*/src/i18n/||'
			return 0
		}
		When call command_substitution
		The output should be blank
	End
End

Describe 'dcc_version_info()'
	Include src/scripts/common.sh

	plain() { sed -E 's/\x1b\[[0-9;]*m//g'; }

	It 'dice la versión de la herramienta y la de bash'
		info() { dcc_version_info | plain; }
		When call info
		The output should include "$DCC_VERSION"
		The output should include "${BASH_VERSION%%(*}"
	End

	# "no me funciona" sin saber qué falta es un correo sin información. Se listan
	# las cinco herramientas de las que depende y DÓNDE está cada una.
	It 'localiza las herramientas de las que depende'
		info() { dcc_version_info | plain; }
		When call info
		The output should include "docker"
		The output should include "jq"
		The output should include "curl"
		The output should include "awk"
		The output should include "tput"
	End

	It 'marca la que NO está instalada en vez de callarse'
		missing_tool() {
			command() { case "$*" in "-v jq") return 1 ;; *) builtin command "$@" ;; esac; }
			dcc_version_info | plain | grep '^  jq'
		}
		When call missing_tool
		The output should include "not installed"
	End

	It 'informa del idioma activo, de su origen y de dónde está la config'
		info() { dcc_version_info | plain; }
		When call info
		The output should include "en"
		The output should include "$DCC_CONFIG"
	End
End
