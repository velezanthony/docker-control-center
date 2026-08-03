# Docker Control Center

Un panel de control de Docker para la terminal. Bash y `make`, sin daemons ni
nada residente.

Te enseña de un vistazo qué contenedores tienes, agrupados por proyecto, cuánta
CPU y RAM consumen, qué volúmenes e imágenes ocupan disco y cuánta basura puedes
borrar. Y te deja operar: arrancar, parar, ver logs, entrar en un contenedor,
hacer copias de seguridad de volúmenes y limpiar.

```bash
make dash
```

## ¿Por qué no `lazydocker`?

Porque resuelven cosas distintas.

| | |
|---|---|
| **`lazydocker`, `ctop`, `dry`** | Interfaces interactivas. Las abres, miras, navegas y sales. Son binarios de Go que hay que instalar. |
| **Esto** | Comandos que imprimen y terminan. Nada que instalar: bash y `make`, que ya tienes. |

Tres diferencias que importan según lo que necesites:

- **Se puede meter en un script.** `make status` imprime y sale, así que encaja
  en un `watch`, en un cron o en un pipe. Una TUI no.
- **Nada que instalar en un servidor.** `git clone` o un fichero de 100 KB. Sin
  binarios, sin gestor de paquetes, sin permisos de root.
- **Los números son verificables.** El campo `Reclaimable` de Docker no cuadra
  con el snapshotter de containerd: `SharedSize` sale 0 en imágenes que sí
  comparten capas base. Aquí nada se estima — todo se cuenta desde los campos
  crudos de la API, y el código documenta de dónde sale cada cifra.

Si lo que quieres es navegar contenedores con el teclado, usa `lazydocker`: es
mejor en eso y no pretendemos competir.

## Para quién está pensado

Para quien usa **Docker Engine nativo en Linux**: el daemon corriendo como
servicio del sistema, sin Docker Desktop de por medio.

Ese escenario es el de un **servidor** o el de un **equipo de desarrollo
Linux**, donde no hay entorno gráfico o simplemente no quieres una aplicación de
escritorio consumiendo memoria solo para enseñarte una lista de contenedores.

Si usas Docker Desktop, esta herramienta no es para ti: ya tienes esa interfaz.

## Para qué sirve

- **Ver el estado real.** Contenedores por stack, coloreados según la gravedad:
  gris si paró bien, amarillo si lo mataron, rojo si murió con error.
- **Saber qué ocupa disco.** Los tamaños se cuentan desde la API, no se
  estiman. Te dice cuánto recuperarías y con qué comando.
- **Operar sin memorizar nombres.** Los comandos abren un menú para elegir el
  contenedor, el volumen o el stack. Y si escribes un nombre mal, te sugiere el
  más parecido.
- **Copias de seguridad de volúmenes.** Un comando para guardarlos y otro para
  restaurarlos.
- **En tu idioma.** Inglés y español, detectado de tu entorno. Sin configurar
  nada.

## Empezar

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/dcc
chmod +x dcc && mv dcc ~/.local/bin/
dcc dash
```

Un fichero, ~100 KB. En [Instalación](users/installation.md) está la otra forma
(clonando el repositorio) y los requisitos.
