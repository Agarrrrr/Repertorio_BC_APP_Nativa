import 'dart:io';

import 'package:flutter/services.dart';

class AndroidSaveFile {
  final File file;
  final String name;

  const AndroidSaveFile({required this.file, required this.name});
}

class AndroidFileSaver {
  AndroidFileSaver._();

  static const _channel = MethodChannel('com.lldm.bc/file_saver');

  static Future<bool> save(List<AndroidSaveFile> files) async {
    if (!Platform.isAndroid || files.isEmpty) return false;
    final saved = await _channel.invokeMethod<bool>('saveFiles', {
      'files': [
        for (final item in files)
          {
            'path': item.file.path,
            'name': item.name,
            'mimeType': 'audio/mpeg',
          },
      ],
    });
    return saved ?? false;
  }
}
