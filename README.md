# Descargador Drive

Aplicación nativa para macOS de **Anthony Marrero · aeternumintelligencecorp** para copiar archivos autorizados de Google Drive a una carpeta local, con interfaz en español y motor [rclone](https://rclone.org/).

**Versión 2.2 · experimental · macOS 13 o posterior · Apple Silicon (M1 o posterior).** La descarga publicada no funciona de forma nativa en Mac Intel. No es un producto oficial de Google.

[Descargar la aplicación](https://github.com/marreroadvisor/Descargador-Drive/releases/tag/v2.2) · [Guía](GUIA.md) · [Limitaciones](#limitaciones)

## Funciones

- Conectar una cuenta de Google Drive mediante el navegador y seleccionar conexiones existentes de rclone.
- Descargar una carpeta por enlace o recorrer unidades compartidas, conservando su estructura.
- Filtrar PDF, documentos, ebooks, imágenes, vídeos, audio, comprimidos y EXE.
- Detectar PDF en unidades compartidas y guardar un inventario local con cantidad y tamaño.
- Mostrar actividad y progreso; volver a iniciar una copia para aprovechar archivos existentes según los criterios de rclone.
- Crear un catálogo CSV de los PDF descargados como punto de partida para una futura extracción RAG. No realiza OCR, embeddings ni consultas de IA.

## Instalación

Descarga `Descargador-Drive-2.2-macOS-arm64.zip` desde Releases, descomprímelo y mueve la aplicación a Aplicaciones. La firma es local (ad hoc), sin notarización de Apple; macOS puede bloquearla. No desactives globalmente Gatekeeper. Revisa el código y las limitaciones antes de usarla.

## Compilar

Requiere Xcode o sus herramientas de desarrollo, macOS y un binario oficial de rclone para Apple Silicon. La publicación incluye rclone 1.75.0; el repositorio no almacena el ejecutable.

```sh
RCLONE_BINARY=/ruta/al/rclone ./scripts/build.sh
```

Resultado: `build/Descargador Drive.app`. El script compila para arm64 y firma localmente la aplicación.

## Privacidad y permisos

No se publican cuentas, tokens, configuraciones de rclone, documentos, inventarios ni registros de transferencias. Cada usuario conecta su propia cuenta. Las credenciales permanecen en la configuración local de rclone, normalmente `~/.config/rclone/rclone.conf`; este archivo es sensible y no debe compartirse. La ubicación puede variar con la configuración del usuario.

La versión 2.2 solicita el alcance completo `drive` al autorizar Google. Aunque la interfaz utiliza operaciones de lectura y copia hacia el Mac, ese permiso es más amplio que solo lectura. Revisa el consentimiento de Google y usa exclusivamente archivos a los que tengas acceso autorizado.

## Limitaciones

- Versión de prueba; no se ha validado aquí una transferencia real ni una autorización nueva de Google.
- El escaneo puede bloquearse con listados grandes porque espera a terminar el proceso antes de vaciar su salida; los errores de algunas consultas no se muestran de forma detallada.
- La cancelación del escaneo no está garantizada en todos los casos y el progreso puede resultar aproximado.
- Los inventarios pueden quedar obsoletos cuando cambia el contenido remoto o la cuenta; vuelve a detectar los PDF antes de usar una selección guardada.
- Se requiere conexión a Internet, acceso a la cuenta y espacio suficiente; las cuotas y restricciones de Google siguen aplicándose.

## Licencia y contribuciones

Código de la aplicación: [MIT](LICENSE). rclone: copyright Nick Craig-Wood, licencia MIT incluida en [Resources/RCLONE-LICENSE.txt](Resources/RCLONE-LICENSE.txt); código de la versión utilizada: https://github.com/rclone/rclone/tree/v1.75.0 . Sus dependencias conservan sus respectivas licencias.

Para errores y mejoras utiliza Issues. No adjuntes tokens, enlaces privados, documentos personales ni inventarios reales.

## English

Native macOS application for authorized Google Drive downloads, shared-drive PDF inventories, file filters and a local CSV catalog. Experimental v2.2, macOS 13+, Apple Silicon only for the supplied binary. Source is MIT licensed; rclone is bundled in the release. Local ad-hoc signature, not Apple-notarized. See the Spanish guide and limitations above. No real Google account transfer was tested for this publication.
