# Alma · app para iPhone y iPad

Navegador con Alma integrada: abre cualquier página (las apps de Spacio AM, GitHub, Google…) y tiene a Alma a un toque, con la página como contexto.

- **Visor** (`WKWebView`) con la misma sesión siempre: entras una vez a Spacio AM y queda.
- **Burbuja de Alma** abajo a la derecha: abre `hub.spacioam.com/alma/` (chat y voz) con la página que estás viendo. En las páginas de Spacio AM no sale, porque ahí Alma ya vive en la roca.
- **«Abrir en Alma»**: `alma://abrir?u=<enlace>` (atajo de Compartir de iOS).
- En la pantalla de inicio se llama **Alma**; la ficha de App Store Connect es «Alma by Spacio AM».

## Cómo se publica
No hace falta Mac. Cada PR se compila en una Mac de GitHub; al dar **Merge** a `main`, el robot (`.github/workflows/testflight.yml`) firma con la llave de App Store Connect y sube la versión a **TestFlight**.

Secretos del repo: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (contenido del archivo `.p8`).

El proyecto de Xcode se genera con [XcodeGen](https://github.com/yonaskolb/XcodeGen) desde `project.yml`.
