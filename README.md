# Mercader

Addon para **World of Warcraft Forever** (cliente Classic, interfaz 16001) que te ayuda con el oro y la experiencia.

## Qué hace

**Contador de sesión.** Una ventana que se puede mover y muestra:
- tiempo de sesión,
- oro ganado, gastado y neto por hora,
- experiencia ganada, experiencia por hora y tiempo estimado para subir de nivel,
- valor de venta de todo lo que llevas en las bolsas y cuánto de eso es gris.

**Comerciante automático.** Al hablar con un vendedor:
- repara todo el equipo, si tienes dinero suficiente,
- vende los objetos grises, uno a uno y comprobando cada hueco antes de vender.

**Precio en el aviso.** Al pasar el ratón por un objeto sale lo que paga el vendedor, por unidad y por montón.

## Instalación

1. Descarga el repositorio (botón **Code → Download ZIP**).
2. Descomprímelo en `World of Warcraft\_forever_\Interface\AddOns\` y renombra la carpeta a `Mercader`.
3. Reinicia el juego (los addons nuevos solo se detectan al arrancar).

## Comandos

| Comando | Qué hace |
|---|---|
| `/merc` | Muestra u oculta la ventana |
| `/merc reset` | Pone el contador a cero |
| `/merc centrar` | Devuelve la ventana a su sitio |
| `/merc bloquear` | Bloquea o desbloquea la ventana |
| `/merc vender` / `reparar` / `precio` | Activa o desactiva cada función |

`/mercader` funciona igual que `/merc`.

## Licencia

MIT (ver `LICENSE`).
