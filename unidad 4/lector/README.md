# Acceso biométrico: Flutter + SQLite + ESP32 + AS608

Ejemplo para exposición con inicio de sesión por nombre/contraseña o nombre/huella y administración de usuarios. Los datos se guardan localmente en cada dispositivo. Las contraseñas se guardan y muestran en texto para esta demostración.

## Preparar Flutter

1. Ejecuta `flutter pub get`.
2. En Windows activa **Modo de desarrollador** en Configuración para permitir los enlaces de los plugins. Para compilar Windows necesitas Visual Studio con la carga de desarrollo de escritorio con C++.
3. Ejecuta `flutter run -d windows` o `flutter run -d <id del dispositivo Android>`.

## Preparar ESP32

1. Abre `firmware/lector_esp32/lector_esp32.ino` en Arduino IDE.
2. Instala el soporte de placas ESP32 de Espressif y la biblioteca **Adafruit Fingerprint Sensor Library** con sus dependencias.
3. Cambia `SSID` y `PASSWORD` por tu red Wi-Fi de 2.4 GHz y selecciona tu placa ESP32.
4. Para ESP32 clásico: TX del AS608 a GPIO16 (RX2), RX del AS608 a GPIO17 (TX2), y GND común. Alimenta VCC según las especificaciones de tu módulo; verifica los pines por su etiqueta, no por el color del cable. Si tu placa reserva GPIO16/17, cambia los pines en el programa.
5. Carga el programa. En el monitor serie a **115200 baudios** aparece la dirección `http://...`.
6. Conecta Android o Windows a la misma red, sin aislamiento entre clientes. En el engrane de la app escribe esa dirección y guarda; se comprueba la conexión al sensor.

## Demostración

- Sin usuarios aparece **Registrar primer usuario**. Configura primero el ESP32.
- Introduce nombre, contraseña y edad. Continúa y coloca el dedo en el lector; retíralo y vuelve a colocar el mismo dedo. El monitor serie muestra estos pasos. Hay un límite de 55 segundos.
- Ingresa con contraseña o cambia a Huella y coloca el dedo al presionar Ingresar.
- La tabla permite consultar, crear, actualizar datos y eliminar usuarios junto con su huella. La eliminaci?n se realiza en SQLite y no necesita el ESP32. Si borras tu propio usuario se cierra la sesión.
- La edición conserva la huella original. Para cambiarla, elimina y vuelve a crear al usuario.

SQLite guarda la **plantilla biom?trica completa como BLOB**, no una imagen ni ?nicamente un identificador. El AS608 genera la plantilla en sus buffers RAM y el ESP32 la transfiere a Flutter para guardarla. No se llama a StoreModel ni a DeleteModel: las huellas permanentes que el lector tenga para otros proyectos permanecen intactas. Los buffers temporales s? se reutilizan: no utilices otro programa con el sensor simult?neamente.

Al verificar, Flutter env?a la plantilla del usuario a trav?s de Wi-Fi. El ESP32 captura el dedo en CharBuffer1, carga la plantilla de SQLite en CharBuffer2 y solicita Match al AS608. No se busca en la biblioteca permanente. Una misma huella puede asociarse a varios nombres; el acceso siempre compara con el usuario escrito. Cada dispositivo conserva su propia SQLite. Se conserva el tama?o recibido (256 a 2048 bytes en bloques de 32); no se garantiza compatibilidad con lectores de otras familias.

### Si ya utilizaste la versi?n anterior

Carga el **nuevo firmware** antes de usar esta versi?n de la app. SQLite se actualiza a la versi?n 2 conservando usuarios, contrase?as y edades. El ID anterior no contiene la plantilla: inicia con contrase?a y pulsa Editar en cada usuario marcado **Pendiente de captura** para capturar su huella en SQLite. Las huellas que la versi?n anterior guard? en la memoria permanente no se borran autom?ticamente; ya no son necesarias para este login. Puedes administrarlas por separado con el programa correspondiente al lector.

## Protocolo HTTP

- `GET /status`: comprueba el lector y devuelve `{"ok":true,"protocol":2}`.
- `POST /enroll`: captura dos veces el dedo y devuelve `{"ok":true,"template":"..."}` con la plantilla completa codificada en hexadecimal (dos caracteres por byte). Flutter los convierte en BLOB.
- `POST /verify`: recibe un formulario `application/x-www-form-urlencoded` con `template` hexadecimal y responde `{"ok":true,"match":true,"score":100}` o `{"ok":true,"match":false}`.
- Los errores devuelven HTTP 400 con `{"ok":false,"message":"..."}`. La ruta `/delete` ya no existe: borrar un usuario elimina su plantilla local.

Las operaciones son secuenciales; utiliza un dispositivo a la vez. No hay modo simulado: el acceso con huella requiere hardware real. Ejecuta `flutter analyze` y `flutter test` para verificar Dart, persistencia BLOB, migraci?n y transporte HTTP. La transferencia UART y la comparaci?n necesitan validaci?n con el ESP32/AS608 f?sico.

Referencias: [SQLite en Windows](https://pub.dev/packages/sqflite_common_ffi), [biblioteca del lector](https://adafruit.github.io/Adafruit-Fingerprint-Sensor-Library/html/class_adafruit___fingerprint.html).

Protocolo UART de referencia: [driver AS608](https://www.libdriver.com/docs/as608/driver__as608_8c.html) (UpChar, DownChar y Match).

## Diagnostico de transferencia

Carga el firmware actualizado y reinicia tambien Flutter. En el monitor serie a 115200 baudios debe aparecer `Firmware SQLite: transferencia variable v3`. Durante el registro se imprime el tipo de paquete, su longitud y el total recibido. El receptor espera el paquete final `0x08` y valida el checksum de cada paquete; no recorta ni rellena plantillas para ajustarlas a 512 bytes. Se conserva la compatibilidad con plantillas anteriores de 512 bytes.

Si la transferencia falla, la aplicacion y el monitor serie muestran la etapa concreta: timeout UART con cantidad recibida, cabecera o checksum incorrectos, codigo de rechazo de UpChar o tamano no admitido. Copia ese mensaje y las lineas `[AS608]` para diagnosticar el sensor fisico. No hace falta borrar SQLite ni la biblioteca permanente del sensor.
