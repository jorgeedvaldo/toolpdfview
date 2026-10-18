import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A PDF the user has opened or starred.
@immutable
class PdfEntry {
  const PdfEntry({required this.path, required this.name, this.openedAt});

  factory PdfEntry.fromPath(String path) =>
      PdfEntry(path: path, name: path.split('/').last);

  factory PdfEntry.fromJson(Map<String, dynamic> json) => PdfEntry(
    path: json['path'] as String,
    name: json['name'] as String? ?? (json['path'] as String).split('/').last,
    openedAt: json['openedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(json['openedAt'] as int),
  );

  final String path;
  final String name;
  final DateTime? openedAt;

  bool get exists => File(path).existsSync();

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    if (openedAt != null) 'openedAt': openedAt!.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) => other is PdfEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Favourites and recently opened documents, persisted on the device.
///
/// Nothing ever leaves the phone: the app only stores file paths.
class Library extends ChangeNotifier {
  static const _recentsKey = 'recents';
  static const _favoritesKey = 'favorites';
  static const _maxRecents = 60;

  SharedPreferences? _prefs;
  List<PdfEntry> _recents = const [];
  List<PdfEntry> _favorites = const [];

  List<PdfEntry> get recents => _recents;
  List<PdfEntry> get favorites => _favorites;

  Future<void> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _recents = _decode(prefs.getString(_recentsKey));
    _favorites = _decode(prefs.getString(_favoritesKey));
    notifyListeners();
  }

  bool isFavorite(String path) => _favorites.any((e) => e.path == path);

  /// Moves [entry] to the top of the recents list.
  Future<void> remember(PdfEntry entry) async {
    final stamped = PdfEntry(
      path: entry.path,
      name: entry.name,
      openedAt: DateTime.now(),
    );
    _recents = [stamped, ..._recents.where((e) => e.path != entry.path)];
    if (_recents.length > _maxRecents) {
      _recents = _recents.sublist(0, _maxRecents);
    }
    await _save(_recentsKey, _recents);
  }

  Future<void> toggleFavorite(PdfEntry entry) async {
    _favorites = isFavorite(entry.path)
        ? _favorites.where((e) => e.path != entry.path).toList()
        : [PdfEntry(path: entry.path, name: entry.name), ..._favorites];
    await _save(_favoritesKey, _favorites);
  }

  Future<void> removeRecent(String path) async {
    _recents = _recents.where((e) => e.path != path).toList();
    await _save(_recentsKey, _recents);
  }

  Future<void> removeFavorite(String path) async {
    _favorites = _favorites.where((e) => e.path != path).toList();
    await _save(_favoritesKey, _favorites);
  }

  Future<void> clearRecents() async {
    _recents = const [];
    await _save(_recentsKey, _recents);
  }

  Future<void> _save(String key, List<PdfEntry> entries) async {
    await _prefs?.setString(
      key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  List<PdfEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PdfEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return const [];
    }
  }
}

/// Single shared instance; loaded once in `main()`.
final Library library = Library();
