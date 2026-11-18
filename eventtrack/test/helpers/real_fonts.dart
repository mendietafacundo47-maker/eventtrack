import 'dart:io';

import 'package:flutter/services.dart';

/// Carga Roboto y los iconos Material del SDK de Flutter para que las
/// pruebas midan anchos reales. La fuente de prueba por defecto dibuja cada
/// carácter como un cuadrado, casi el doble de ancho que Roboto, y daría
/// desbordes que no existen en el navegador.
Future<void> loadRealFonts() async {
  // flutter_tester está dentro del SDK: se busca hacia arriba la carpeta.
  Directory? dir;
  for (
    var d = File(Platform.resolvedExecutable).parent;
    d.parent.path != d.path;
    d = d.parent
  ) {
    final candidate = Directory('${d.path}/bin/cache/artifacts/material_fonts');
    if (candidate.existsSync()) {
      dir = candidate;
      break;
    }
  }
  if (dir == null) return;
  final fonts = dir;

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('${fonts.path}/$f');
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}
