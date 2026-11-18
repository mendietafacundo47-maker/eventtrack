import 'package:flutter/widgets.dart';

// Un solo proyecto Flutter, dos clientes (§4.3.2, §4.5.5): en Android la app
// del responsable; en el navegador el panel administrativo. La importación
// condicional evita compilar sqflite y dart:io para la web.
import 'bootstrap/bootstrap_mobile.dart'
    if (dart.library.js_interop) 'bootstrap/bootstrap_web.dart'
    as platform;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await platform.bootstrap();
}
