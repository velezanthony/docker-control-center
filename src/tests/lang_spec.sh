# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2329  # falsos positivos del DSL
#
# write_cfg() es el único código que toca un fichero del usuario: va a un temporal.

Describe 'known()'
	Include src/scripts/lang.sh

	Parameters
		en success
		es success
		fr failure
		"" failure
	End

	It "'$1' -> $2"
		When call known "$1"
		The status should be "$2"
	End
End

Describe 'name_of()'
	Include src/scripts/lang.sh

	# Importante que NO haga source del catálogo: cargarlos todos machacaría el
	# MSG del idioma activo y el menú saldría en idiomas mezclados.
	Parameters
		en English success
		es Español success
		xx ""      failure   # un catálogo inexistente devuelve 2, no revienta
	End

	It "el nombre de '$1' sale del catálogo sin cargarlo"
		When call name_of "$1"
		The output should equal "$2"
		The status should be "$3"
	End
End

Describe 'write_cfg()'
	Include src/scripts/lang.sh

	setup()   { TMP=$(mktemp -d); DCC_CONFIG="$TMP/.config"; }
	cleanup() { rm -rf "$TMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	It 'crea el fichero con cabecera si no existía'
		write_new() { write_cfg es; printf '%s|%s' "$(_dcc_cfg_get DCC_LANG)" "$(<"$DCC_CONFIG")"; }
		When call write_new
		The output should start with "es|"
		The output should include "#"
	End

	# Es la preferencia del usuario: si mañana guardamos otra clave ahí, cambiar
	# el idioma no puede borrarla.
	It 'CONSERVA el resto del fichero'
		overwrite() {
			printf '# mi cabecera\nOTRA_COSA=valor\nDCC_LANG=es\nTERCERA=3\n' >"$DCC_CONFIG"
			write_cfg en
			printf '%s|%s|%s|%s' "$(_dcc_cfg_get DCC_LANG)" "$(_dcc_cfg_get OTRA_COSA)" \
			                     "$(_dcc_cfg_get TERCERA)" "$(<"$DCC_CONFIG")"
		}
		When call overwrite
		The output should start with "en|valor|3|"
		The output should include "mi cabecera"
	End

	It 'no duplica la clave al reescribirla tres veces'
		rewrite_thrice() { write_cfg es; write_cfg en; write_cfg es; grep -c '^DCC_LANG=' "$DCC_CONFIG"; }
		When call rewrite_thrice
		The output should equal "1"
	End

	# Acababa en `cp …; rm -f "$tmp"`, así que el estado de la función era el del
	# rm —siempre 0— y apply() pintaba "✓ Guardado en …" con el fichero intacto.
	Describe 'cuando la escritura FALLA'
		# root ignora los bits de permiso, así que el fallo no se puede provocar.
		# En CI dentro de un contenedor se corre como root: sin esto, estos cuatro
		# ejemplos fallarían por el entorno y no por el código.
		as_root() { [ "$(id -u)" -eq 0 ]; }

		unwritable() {
			printf '# previo\n' >"$DCC_CONFIG"
			chmod 0444 "$DCC_CONFIG"; chmod 0555 "$TMP"
		}
		restore() { chmod 0755 "$TMP" 2>/dev/null; chmod 0644 "$DCC_CONFIG" 2>/dev/null; }
		AfterEach 'restore'
		Skip if "root se salta los permisos" as_root

		It 'devuelve != 0 en vez de mentir'
			fails_loudly() { unwritable; write_cfg es; }
			When call fails_loudly
			The status should be failure
		End

		It 'deja el fichero anterior intacto'
			keeps_old() { unwritable; write_cfg es || true; cat "$DCC_CONFIG"; }
			When call keeps_old
			The output should equal "# previo"
		End

		It 'no deja temporales tirados'
			no_leak() { unwritable; write_cfg es || true; find "$TMP" -name '.config.*' | wc -l; }
			When call no_leak
			The output should equal "0"
		End

		# El usuario tiene que enterarse: nada de ✓ verde sobre una escritura fallida.
		It 'apply() avisa en rojo y NO pinta el ✓'
			no_tick() { unwritable; ENV_LANG=""; apply es 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g'; }
			When call no_tick
			The status should be failure
			The output should include "not saved"
			The output should not include "✓"
		End
	End

	# Con DCC_CONFIG=/dev/null el `mv` reemplazaría el nodo de dispositivo.
	It 'se niega a escribir sobre algo que no es un fichero normal'
		on_device() { DCC_CONFIG=/dev/null; write_cfg es; }
		When call on_device
		The status should be failure
	End

	It 'con valor vacío BORRA la preferencia pero deja el resto'
		clear_pref() {
			printf 'OTRA_COSA=valor\n' >"$DCC_CONFIG"
			write_cfg es
			write_cfg ""
			_dcc_cfg_get DCC_LANG && printf 'SIGUE'
			printf '%s' "$(_dcc_cfg_get OTRA_COSA)"
		}
		When call clear_pref
		The output should equal "valor"
	End
End

Describe 'origin_text()'
	Include src/scripts/lang.sh

	setup() { DCC_CONFIG="/tmp/dcc-test-config"; }
	BeforeEach 'setup'

	Describe 'nombra el origen'
		Parameters
			env     DCC_LANG
			locale  locale
			default default
		End

		It "el idioma vino de: $1"
			origin_of() { DCC_LANG_ORIGIN="$1"; origin_text; }
			When call origin_of "$1"
			The output should include "$2"
		End
	End

	It 'cuando viene del fichero, dice cuál'
		from_file() { DCC_LANG_ORIGIN="config"; origin_text; }
		When call from_file
		The output should include "$DCC_CONFIG"
	End
End

Describe 'codes()'
	Include src/scripts/lang.sh

	It 'lista los catálogos disponibles, ordenados'
		list_codes() { codes | tr '\n' ' '; }
		When call list_codes
		The output should equal "en es "
	End
End

Describe 'show_current()'
	Include src/scripts/lang.sh

	plain() { sed -E 's/\x1b\[[0-9;]*m//g'; }

	It 'dice qué idioma está activo, con su nombre y de dónde viene'
		current() {
			ENV_LANG=""; DCC_LANG_RESOLVED=en; DCC_LANG_ORIGIN="env"
			show_current | plain
		}
		When call current
		The output should include "Current language"
		The output should include "English"
		The output should include "DCC_LANG"
	End
End

# Con DCC_LANG exportado el entorno gana al fichero y el comando no sirve de nada.
Describe 'warn_env_blocks()'
	Include src/scripts/lang.sh

	It 'sin DCC_LANG exportado no molesta'
		quiet() { ENV_LANG=""; warn_env_blocks; }
		When call quiet
		The status should be success
		The output should be blank
	End

	It 'con DCC_LANG exportado avisa EN ROJO'
		warn() { ENV_LANG=es; warn_env_blocks; }
		When call warn
		The output should include "$RD"
		The output should include "has NOT taken effect"
	End

	It 'y da el comando exacto que lo arregla'
		warn() { ENV_LANG=es; warn_env_blocks | sed -E 's/\x1b\[[0-9;]*m//g'; }
		When call warn
		The output should include "unset DCC_LANG"
	End
End

Describe 'apply()'
	Include src/scripts/lang.sh

	setup() {
		TMP=$(mktemp -d); DCC_CONFIG="$TMP/.config"; ENV_LANG=""
		# apply() hace `unset DCC_LANG` y la resolución cae al locale del sistema.
		# C y no en_US.UTF-8, que puede no estar generado. No se fija global
		# porque en C, ${#s} cuenta bytes y rompería pad().
		LC_ALL=C
	}
	cleanup() { rm -rf "$TMP"; unset DCC_LANG; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	plain() { sed -E 's/\x1b\[[0-9;]*m//g'; }

	It 'guarda la preferencia en el fichero'
		set_es() { apply es >/dev/null 2>&1; _dcc_cfg_get DCC_LANG; }
		When call set_es
		The output should equal "es"
	End

	# dcc_load_language existe para poder repetirse: sin ella habría que relanzar
	# el proceso, y en el fichero único no hay `. common.sh` que valga.
	It 'RECARGA el catálogo en el acto, sin relanzar nada'
		set_es() { apply es >/dev/null 2>&1; }
		When call set_es
		The variable DCC_LANG_RESOLVED should eq "es"
	End

	It 'confirma en el idioma NUEVO, no en el viejo'
		set_es() { apply es 2>/dev/null | plain; }
		When call set_es
		The output should include "Idioma fijado a"
		The output should include "Español"
	End

	It 'dice DÓNDE lo ha guardado, para que sepas qué borrar'
		set_es() { apply es 2>/dev/null | plain; }
		When call set_es
		The output should include "$DCC_CONFIG"
	End

	It 'auto borra la preferencia y vuelve a la autodetección'
		reset() {
			apply es >/dev/null 2>&1
			apply auto >/dev/null 2>&1
			_dcc_cfg_get DCC_LANG && printf 'LA PREFERENCIA SIGUE AHÍ'
			printf 'limpio'
		}
		When call reset
		The output should equal "limpio"
	End

	# Si el entorno va a tapar el cambio, pintar el ✓ verde de "todo bien" sería
	# mentir: el comando no ha surtido efecto.
	It 'con DCC_LANG exportado NO pinta el ✓ de todo bien'
		blocked() { ENV_LANG=es; apply en 2>/dev/null | plain; }
		When call blocked
		The output should not include "✓"
		The output should include "•"
	End

	It 'y en ese caso avisa además de por qué no ha servido'
		blocked() { ENV_LANG=es; apply en 2>/dev/null | plain; }
		When call blocked
		The output should include "unset DCC_LANG"
	End
End

# lang_main() llama a `exit`, así que va con `When run`: con `When call`
# ShellSpec aborta el ejemplo.
Describe 'lang_main()'
	Include src/scripts/lang.sh

	setup() {
		TMP=$(mktemp -d); DCC_CONFIG="$TMP/.config"; ENV_LANG=""
		# apply() hace `unset DCC_LANG` y la resolución cae al locale del sistema.
		# C y no en_US.UTF-8, que puede no estar generado. No se fija global
		# porque en C, ${#s} cuenta bytes y rompería pad().
		LC_ALL=C
	}
	cleanup() { rm -rf "$TMP"; unset DCC_LANG; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	It 'con un código válido lo fija y sale con 0'
		When run lang_main es
		The status should be success
		The output should include "Idioma fijado a"
	End

	It 'auto vuelve a la autodetección'
		When run lang_main auto
		The status should be success
		The output should include "auto-detection"
	End

	Describe 'acepta los tres sinónimos de "vuelve a como estaba"'
		Parameters
			auto
			reset
			unset
		End

		It "'$1' borra la preferencia"
			When run lang_main "$1"
			The status should be success
			The output should include "auto-detection"
		End
	End

	# Un código inventado no puede salir con 0: quien encadene `dcc lang xx && …`
	# seguiría creyendo que lo cambió.
	It 'un código inventado sale con 1 y NO lo guarda'
		When run lang_main klingon
		The status should eq 1
		The output should include "klingon"
	End

	It 'y en vez de dejarte tirado, lista los que sí existen'
		When run lang_main klingon
		The status should eq 1
		The output should include "en, es"
	End

	# `paste -sd', '` trata su argumento como una LISTA de delimitadores que ROTA:
	# con dos idiomas daba "en,es" y colaba, con tres "en,es fr" y con cuatro
	# "en,es fr,de". Este test finge un tercer catálogo para que no vuelva.
	It 'con TRES idiomas el separador sigue siendo el mismo'
		three_langs() {
			codes() { printf 'de\nen\nes\n'; }
			name_of() { printf 'X'; }
			lang_main klingon
		}
		When run three_langs
		The status should eq 1
		The output should include "de, en, es"
	End

	# Sin terminal (una tubería, CI) un `select` se cuelga o sale en vacío. Ahí se
	# lista lo que hay y se explica cómo elegir, y punto.
	It 'sin argumento y sin terminal NO abre un menú: lista y explica'
		When run lang_main
		The status should be success
		The output should include "Current language"
		The output should include "lang en"
		The output should include "lang auto"
	End
End
