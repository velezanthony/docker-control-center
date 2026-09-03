# ==============================================================================
#  bytes.jq — formateador de bytes ÚNICO de todo el proyecto.
#
#  No es un módulo con `include`: se antepone como TEXTO al programa que lo
#  necesita (JQ_BYTES en common.sh), porque el fichero único no lleva .jq que
#  ofrecerle a jq -L.
#
#  Nada de numfmt: respeta el locale y escupe "5,1GB" (coma decimal, sin
#  espacio) mientras jq da "8.88 GB" -> dos estilos en la misma pantalla.
#  Un solo formateador o ninguno.
# ==============================================================================
def h: if . == null or . == 0 then "0 B"
	elif . >= 1e9 then ((. / 1e9 * 100 | floor) / 100 | tostring) + " GB"
	elif . >= 1e6 then ((. / 1e6) | floor | tostring) + " MB"
	elif . >= 1e3 then ((. / 1e3) | floor | tostring) + " kB"
	else (tostring) + " B" end;
