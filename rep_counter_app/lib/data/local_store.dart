// Small JSON documents on disk: the offline copy of the user's data and the
// queue of changes not yet uploaded. Files instead of SharedPreferences
// because the history keeps growing.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract class LocalStore {
  Future<String?> read(String name);
  Future<void> write(String name, String data);

  /// Deletes every document whose name starts with [prefix].
  Future<void> deleteAll(String prefix);
}

class FileLocalStore implements LocalStore {
  Directory? _root;

  Future<Directory> _dir() async =>
      _root ??= Directory('${(await getApplicationSupportDirectory()).path}/data');

  Future<File> _file(String name) async => File('${(await _dir()).path}/$name');

  @override
  Future<String?> read(String name) async {
    final file = await _file(name);
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String name, String data) async {
    final file = await _file(name);
    await file.parent.create(recursive: true);
    // Write aside and rename: a crash mid-write never leaves half a file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> deleteAll(String prefix) async {
    final target = Directory('${(await _dir()).path}/$prefix');
    if (await target.exists()) await target.delete(recursive: true);
  }
}

class MemoryLocalStore implements LocalStore {
  final Map<String, String> files = {};

  @override
  Future<String?> read(String name) async => files[name];

  @override
  Future<void> write(String name, String data) async => files[name] = data;

  @override
  Future<void> deleteAll(String prefix) async =>
      files.removeWhere((k, _) => k.startsWith(prefix));
}
