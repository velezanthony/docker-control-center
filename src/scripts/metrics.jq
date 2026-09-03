# ==============================================================================
#  metrics.jq — cuenta la basura y el disco desde la salida cruda de /system/df.
#
#  Vive en un FICHERO y no dentro de una cadena de bash por dos razones: se
#  puede validar —`make lint` lo hace, concatenándole bytes.jq delante porque
#  aquí se usa h() y `jq -n -f` a secas fallaría con "h/0 is not defined"— y se
#  lee sin contar comillas. Dentro de un '...' ni shellcheck ni los tests ven
#  nada: un `|` de más se descubre en pantalla, en producción.
#
#  Salida: pares CLAVE<TAB>VALOR, que dashboard.sh mete en el array M.
#
#  REGLA: NO se usa el campo .Reclaimable de Docker. Con el snapshotter de
#  containerd no cuadra — su fórmula LayersSize - Σ(Size-SharedSize) no coincide
#  con lo que imprime el CLI, porque SharedSize sale 0 en imágenes que SÍ
#  comparten capas base. Cada métrica se cuenta aquí desde los campos crudos.
# ==============================================================================

# El formateador de bytes vive en bytes.jq y se comparte con el resto de
# consultas del dashboard: un solo formato en toda la pantalla.
# (h() viene de bytes.jq, que common.sh concatena delante de este programa)

def sum(f): [f] | add // 0;
# Cada métrica se COTEJA con un campo crudo, nunca con .Reclaimable
(.BuildCache // []) as $bc | (.Images // []) as $im
| (.Containers // []) as $co | (.Volumes // []) as $vo
| sum($bc[] | select(.InUse == false) | .Size)                      as $cacheSz
| ([$bc[] | select(.InUse == false)] | length)                      as $cacheN
| sum($co[] | select(.State != "running") | .SizeRw)                as $stopSz
| ([$co[] | select(.State != "running")] | length)                  as $stopN
| sum($im[] | select(.Containers == 0) | .Size)                     as $imgSz
| ([$im[] | select(.Containers == 0)] | length)                     as $imgN
| sum($vo[] | select(.UsageData.RefCount == 0) | .UsageData.Size)   as $volSz
| ([$vo[] | select(.UsageData.RefCount == 0)] | length)             as $volN
| [$im[] | select(.Containers == 0) | ((.RepoTags // ["<none>"])[0] | split(":")[0])] as $imgNames
| sum($vo[] | .UsageData.Size) as $volTotal | sum($co[] | .SizeRw) as $coTotal
| sum($bc[] | .Size) as $bcTotal | (.LayersSize // 0) as $layers
| (
  "cacheN\t\($cacheN)", "cacheSz\t\($cacheSz | h)", "cacheRaw\t\($cacheSz)",
  "stopN\t\($stopN)",   "stopSz\t\($stopSz | h)",   "stopRaw\t\($stopSz)",
  "imgN\t\($imgN)",     "imgSz\t\($imgSz | h)",     "imgRaw\t\($imgSz)",
  "imgNames\t\($imgNames | join(", "))",
  "volN\t\($volN)",     "volSz\t\($volSz | h)",     "volRaw\t\($volSz)",
  "trash\t\($cacheSz + $stopSz + $imgSz + $volSz | h)",
  "disk\t\($layers + $coTotal + $volTotal + $bcTotal | h)",
  "layers\t\($layers | h)",   "volTotal\t\($volTotal | h)",
  "coTotal\t\($coTotal | h)", "bcTotal\t\($bcTotal | h)"
  )
