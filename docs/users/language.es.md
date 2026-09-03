# Idioma

La interfaz está en **inglés y español**, y solo en esos dos. Sin configurar
nada, se elige sola a partir de tu locale — y casa por **región**, no solo por
idioma: `es`, `es_ES`, `es-AR` y `es.UTF-8` te dan español, y también `ca_ES`,
`gl_ES`, `eu_ES` e incluso `en_ES`, porque acaban en `_ES`. Cualquier otro valor
cae a inglés.

Te toque el que te toque, hay salida que no se traduce nunca, y una línea de uso
cableada en español elijas lo que elijas.
[Limitaciones](limitations.md#idioma) dice exactamente cuál.

## Cambiarlo

=== "Repositorio"
    ```bash
    make lang           # menú
    make lang en        # directo
    make lang auto      # volver a la detección automática
    ```

=== "Fichero único"
    ```bash
    dcc lang
    dcc lang en
    dcc lang auto
    ```

```
  Idioma actual: es Español (detectado del locale de tu sistema)

  Elige un idioma:
1) en — English          3) auto — detectarlo del sistema
2) es — Español

>
```

Cambia el idioma de **todos** los comandos. Se guarda en
`~/.config/dcc/config`, siguiendo el estándar XDG: es tuyo, no del proyecto, y
sobrevive a actualizar la herramienta.

## Para un solo comando

```bash
DCC_LANG=es make run dash      # solo esta vez
```

Precedencia completa:

```
DCC_LANG  >  ~/.config/dcc/config  >  $LC_ALL  >  $LC_MESSAGES  >  $LANG  >  inglés
```

Las tres variables de locale se leen en ese orden, el mismo que usa la librería
de C. `LC_ALL` es la que pilla a la gente: exportada por un script o por un job
de CI, le gana al `LANG` que hayas puesto tú. Y decide más cosas que el idioma:
en un locale que no sea UTF-8, como `LC_ALL=C`, el relleno cuenta bytes y las
columnas acentuadas del español se descuadran —
[Limitaciones](limitations.md#salida-y-terminal) trae los números.

!!! warning "No exportes `DCC_LANG`"
    Si lo dejas exportado en tu terminal le gana al fichero y `lang` parecerá
    roto. Úsalo delante de un comando concreto, como arriba. Si te pasa, `lang`
    te lo dice y te da el `unset`.

!!! question "¿Por qué un fichero y no una variable a secas?"
    Un proceso hijo no puede modificar el entorno de su padre. Si `lang` hiciera
    `export`, esa variable moriría con el proceso y tu terminal no se enteraría
    jamás. Ningún comando puede cambiarte una variable de entorno — pero sí puede
    escribir un fichero que todos los scripts leen al arrancar.

## Añadir un idioma

Copia `src/i18n/en.sh` a `src/i18n/<código>.sh`, traduce los valores y añade tu
código al `case` de `dcc_load_language()`, dentro de `src/scripts/common.sh`.
Luego ejecuta `make bundle`: el fichero único lleva los catálogos incrustados y
no verá el nuevo hasta que lo reconstruyas.

Tres cosas que no te van a avisar:

- **El catálogo solo no es un idioma.** `dcc lang <código>` acepta cualquier
  código que exista como fichero en `src/i18n/`, así que si te saltas el `case`
  verás igualmente `✓ Language set to Français.`, la preferencia guardada y
  código de salida `0` — en inglés, porque `apply()` recarga el idioma antes de
  imprimirlo. A partir de ahí todo sale en inglés y `dcc version` informa de
  `language en (config)`. El ✓ es verde y nadie se queja.
- **No hay respaldo al inglés.** `dcc_load_language()` hace `MSG=()` y carga un
  catálogo, y solo uno, así que una clave que se te olvide le llega al usuario
  con su propio nombre: `op_started`.
- **El test de paridad no mirará tu fichero.** El de `src/tests/common_spec.sh`
  tiene cableados `en.sh` y `es.sh`. Amplíalo con tu idioma, o una traducción a
  medias pasará `make check` en verde.
