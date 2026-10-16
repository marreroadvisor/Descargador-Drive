# Guía de uso

1. Abre Descargador Drive y pulsa **Conectar Google Drive**. Completa tú la autorización en Google; la versión 2.2 solicita acceso completo a Drive.
2. Si ya tienes conexiones locales de rclone, elige la correcta en **Conexión**. Confirma que ves las unidades de la cuenta esperada.
3. Para recorrer todas las unidades compartidas, conserva activada esa opción. Para descargar una carpeta por enlace, desactívala y pega el enlace de la carpeta. Para trabajar con una unidad concreta, desactívala, elige la unidad y utiliza el enlace de la página de unidades compartidas de Drive.
4. Elige una carpeta de destino y los tipos de archivo.
5. **Detectar PDF** crea un inventario de las unidades compartidas; no escanea el enlace de una carpeta individual. **Descargar inteligente** copia los archivos al Mac. El catálogo CSV se genera al terminar correctamente todos los trabajos.
6. Consulta el registro y comprueba los archivos recibidos. Si la aplicación se queda esperando durante un escaneo grande, consulta las limitaciones del README.

No compartas `rclone.conf`, inventarios, manifiestos, registros ni catálogos con datos personales. La aplicación no proporciona un servidor en la nube ni acceso permanente a Google. Puedes revocar su acceso desde tu cuenta de Google.
