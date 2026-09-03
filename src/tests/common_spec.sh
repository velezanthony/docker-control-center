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

# Con IFS=TAB bash colapsa los separadores seguidos y la fila se corre un puesto.
# OJO: $SEP (\x1f) no puede viajar por los argumentos de `When` — aborta la suite
# con código 102 aunque los tests pasen. Cada caso arma su cadena DENTRO.
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

	# Solo hace falta el VALOR: dcc_load_language casa el patrón, no cambia el
	# locale. Pero el prefijo `LC_ALL=… cmd` sí intenta aplicarlo y bash avisa por
	# stderr si no está generado. Por eso se asigna DENTRO de la función.
	It 'sabe que el idioma vino del locale'
		origin_of() {
			unset DCC_LANG
			( LC_ALL=es_ES.UTF-8; dcc_load_language; printf '%s' "$DCC_LANG_ORIGIN" ) 2>/dev/null
		}
		When call origin_of
		The output should equal "locale"
	End
End

# Los catálogos se cargan con `source`, así que unas comillas invertidas o un
# $( ) no son texto: son EJECUCIÓN. Pasó con [help_link]="… `dcc` …", que
# reventaba `make run` entero. ${DCC_CMD} sí vale: es expansión de parámetro.
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

# El formato `nombre: ## texto` se parseaba en CUATRO sitios con cuatro reglas
# distintas. Ahora en uno. Estos son los casos que las hacían discrepar.
Describe 'dcc_parse_commands()'
	Include src/scripts/common.sh

	Describe 'names: qué cuenta como comando'
		Parameters
			'dash: ## texto'        dash          'lo normal'
			'stack-start: ## texto' stack-start   'con guión'
			'ps2: ## texto'         ps2           'con dígito'
			'psa: ps  ## alias'     psa           'con dependencia delante del ##'
		End

		It "$3"
			names_of() { printf '%s\n' "$1" | dcc_parse_commands names; }
			When call names_of "$1"
			The output should equal "$2"
		End
	End

	Describe 'names: qué NO cuenta, y por eso dispatch lo rechazaba'
		Parameters
			'Foo: ## texto'       'empieza por mayúscula'
			'mi_target: ## texto' 'lleva guión bajo'
			'.PHONY: help'        'no lleva ##'
			'# dash: ## texto'    'es un comentario'
			'##@ Overview'        'es una sección, no un comando'
		End

		It "$2"
			names_of() { printf '%s\n' "$1" | dcc_parse_commands names; }
			When call names_of "$1"
			The output should be blank
		End
	End

	It 'lines conserva las secciones y names las descarta'
		both() {
			printf '##@ Overview\ndash: ## texto\n' | dcc_parse_commands lines
			printf -- '---\n'
			printf '##@ Overview\ndash: ## texto\n' | dcc_parse_commands names
		}
		When call both
		The output should equal "##@ Overview
dash: ## texto
---
dash"
	End

	# Un `case` de bash lo daba por bueno porque el TAB no cuenta como \t en el
	# patrón. El awk ancla en el principio de línea y no hay discusión.
	It 'una receta sangrada con TAB que lleva : y ## no es un comando'
		recipe() { printf '\t@printf "no: soy ## un comentario"\n' | dcc_parse_commands names; }
		When call recipe
		The output should be blank
	End
End

# El pie del panel decía, LITERALMENTE, "dcc help · make clean · make clean-build".
# Quien se baja el fichero suelto no tiene Makefile: se le mandaba a un comando
# que no existe en su máquina. Y las docs prometían `make dash`, `make logs` y
# `make volume-backup-all`, que tampoco son targets. El prefijo lo pone DCC_CMD.
#
# `make lang` sí vale: es un target de verdad. La regla no es "nada de make",
# es "nada de `make <algo>` que no exista".
Describe 'nadie promete un make que no existe'
	# Los comandos del producto que NO son además un target del Makefile.
	fake_targets() {
		local c
		while read -r c; do
			[ -n "$c" ] || continue
			grep -qE "^${c}:" "$REPO_ROOT/Makefile" || printf '%s\n' "$c"
		done < <(grep -oE '^[a-z][a-z0-9-]*:' "$REPO_ROOT/src/commands.txt" | tr -d ':')
	}

	It 'ni los catálogos, en sus líneas de VALOR'
		# Solo las líneas de valor: un comentario `# --- make help ---` no le
		# promete nada a nadie.
		in_catalogs() {
			local c f
			while read -r c; do
				for f in "$REPO_ROOT"/src/i18n/*.sh; do
					grep -E '^[[:blank:]]*\[[a-z0-9_-]+\]=' "$f" \
					| grep -E "make ${c}([^a-z0-9-]|$)" \
					| sed "s|^|$(basename "$f") |"
				done
			done < <(fake_targets)
			return 0
		}
		When call in_catalogs
		The output should be blank
	End

	# docs/ y el README son la promesa que lee alguien que aún no ha clonado nada.
	# El .gitignore entró después: su aviso —el que evita publicar tus volúmenes—
	# mandaba a `make volume-backup` y sobrevivió a la mudanza de los comandos
	# justo porque esta lista no lo miraba.
	#
	# CONTRIBUTING.md se queda FUERA a propósito: ahí `make clean` aparece citado
	# como el ejemplo de lo que la regla prohíbe, y prohibir el antipatrón en el
	# texto que lo explica deja la regla sin poder enseñarse.
	It 'ni la documentación, ni el README, ni el .gitignore'
		in_docs() {
			local c f
			while read -r c; do
				for f in "$REPO_ROOT"/docs/*.md "$REPO_ROOT"/docs/*/*.md \
				         "$REPO_ROOT/README.md" "$REPO_ROOT/.gitignore"; do
					[ -f "$f" ] || continue
					grep -nE "make ${c}([^a-z0-9-]|$)" "$f" | sed "s|^|$(basename "$f"):|"
				done
			done < <(fake_targets)
			return 0
		}
		When call in_docs
		The output should be blank
	End
End

# El asset de una release toma el BASENAME del fichero que sube el workflow. Se
# publicaba como docker-control-center.sh mientras el README, las dos páginas de
# instalación, las dos portadas y las propias notas de la release mandaban a
# descargar `dcc`. Nunca saltó porque el proyecto aún no tiene ninguna etiqueta:
# habría reventado en la primera, con cinco 404 en la cara del primer usuario.
Describe 'la URL de descarga apunta al fichero que se publica'
	asset() {
		awk '/^ *files:/ { sub(/^ *files: */, ""); n = split($0, p, "/"); print p[n]; exit }' \
			"$REPO_ROOT/.github/workflows/release.yml"
	}

	It 'release.yml publica un asset con nombre'
		When call asset
		The output should not be blank
	End

	It 'y nadie manda a descargar otro nombre'
		mismatched() {
			local a f
			a=$(asset)
			for f in "$REPO_ROOT/README.md" "$REPO_ROOT"/docs/*.md "$REPO_ROOT"/docs/*/*.md \
			         "$REPO_ROOT/.github/workflows/release.yml"; do
				[ -f "$f" ] || continue
				# La URL de release.yml lleva ${{ … }} en medio, con espacios: se
				# neutraliza antes, o el último campo acaba siendo la llave.
				sed 's/[$]{{[^}]*}}/TAG/g' "$f" \
				| grep -oE 'releases/[A-Za-z/]*download/[^ )"]+' \
				| sed -E 's|.*/||' \
				| grep -vxF "$a" \
				| sed "s|^|$(basename "$f"): |"
			done
			return 0
		}
		When call mismatched
		The output should be blank
	End
End

# CONTRIBUTING.md, CHANGELOG.md y SECURITY.md son páginas del sitio: los stubs
# de docs/ no tienen contenido propio, los incrustan con pymdownx.snippets.
# Viven en la RAÍZ, que no es docs/, así que hay que nombrarlos en los `paths`
# del workflow o editarlos no reconstruye nada y el sitio publicado se queda con
# la versión vieja. No falla de forma visible: simplemente no corre.
#
# Y la lista va DUPLICADA a propósito (los anchors de YAML no son fiables en
# Actions), así que se vigilan las dos cosas: que estén, y que los dos bloques
# no hayan divergido.
Describe 'el workflow del sitio se dispara con todo lo que el sitio publica'
	# Entradas del n-ésimo bloque `paths:`, sin comillas ni comentario al final.
	# Sin extensiones GNU en awk: `[ \t]` explícito y nada de [[:space:]].
	paths_of() {
		awk -v want="$1" '
			/^[ \t]*paths:[ \t]*$/ { n++; inp = 1; next }
			inp && /^[ \t]*-[ \t]/ {
				if (n == want) {
					sub(/^[ \t]*-[ \t]*/, "")
					sub(/[ \t]*#.*$/, "")
					gsub(/"/, "")
					sub(/[ \t]+$/, "")
					print
				}
				next
			}
			{ inp = 0 }
		' "$REPO_ROOT/.github/workflows/docs.yml"
	}

	# Lo que los stubs incrustan y además existe en la raíz del repositorio.
	embedded_roots() {
		local m
		sed -nE 's/^--8<--[[:blank:]]+"([^"]+)".*/\1/p' "$REPO_ROOT"/docs/*.md \
		| sort -u \
		| while IFS= read -r m; do [ -f "$REPO_ROOT/$m" ] && printf '%s\n' "$m"; done
		return 0
	}

	# Si el awk deja de casar, los dos tests de abajo compararían listas vacías
	# contra listas vacías y pasarían en verde sin vigilar nada.
	It 'docs.yml declara los dos bloques de paths'
		both_blocks() { [ -n "$(paths_of 1)" ] && [ -n "$(paths_of 2)" ]; }
		When call both_blocks
		The status should be success
	End

	It 'y cada fichero de la raíz que el sitio incrusta está en la lista'
		unwatched() {
			local m
			while IFS= read -r m; do
				paths_of 1 | grep -qxF "$m" || printf '%s\n' "$m"
			done < <(embedded_roots)
			return 0
		}
		When call unwatched
		The output should be blank
	End

	It 'y el bloque de push y el de pull_request dicen lo mismo'
		diverged() { diff <(paths_of 1) <(paths_of 2); }
		When call diverged
		The output should be blank
	End
End

# `dcc_load_language()` hace `MSG=()` y carga UN catálogo: no hay respaldo al
# inglés. Una clave que falte en es.sh no sale traducida ni sin traducir — sale
# el NOMBRE de la clave, `op_started`, en la cara del usuario. Verificado.
Describe 'los catálogos tienen exactamente las mismas claves'
	keys_of() { grep -oE '^[[:blank:]]*\[[a-z0-9_-]+\]' "$1" | tr -d ' \t[]' | sort; }

	It 'ninguna clave de en.sh falta en es.sh'
		missing_in_es() {
			comm -23 <(keys_of "$REPO_ROOT/src/i18n/en.sh") <(keys_of "$REPO_ROOT/src/i18n/es.sh")
		}
		When call missing_in_es
		The output should be blank
	End

	# Al revés también: una clave que solo existe en es.sh es peso muerto, y
	# señal de que en.sh —el idioma fuente— se quedó atrás.
	It 'ni sobra ninguna en es.sh que en.sh no tenga'
		extra_in_es() {
			comm -13 <(keys_of "$REPO_ROOT/src/i18n/en.sh") <(keys_of "$REPO_ROOT/src/i18n/es.sh")
		}
		When call extra_in_es
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

# DCC_CMD es el prefijo con el que la herramienta se cita a sí misma. Valía
# `make` a secas, herencia de cuando el Makefile tenía targets de producto: hoy
# no tiene ninguno, así que el panel mandaba a `make clean`, que no existe.
Describe 'DCC_CMD se cita a sí mismo con algo que existe'
	Include src/scripts/common.sh

	It 'por defecto nombra un target REAL del Makefile'
		target_exists() { grep -qE "^${DCC_CMD#make }:" "$REPO_ROOT/Makefile"; }
		When call target_exists
		The status should be success
	End

	It 'y el entorno lo puede cambiar: el bundle se llama de otra forma'
		as_bundle() { DCC_CMD=dcc; printf '%s' "$DCC_CMD"; }
		When call as_bundle
		The output should equal "dcc"
	End
End
