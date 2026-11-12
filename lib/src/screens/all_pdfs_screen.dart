import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../services/library.dart';
import '../services/storage.dart';
import '../widgets/document_tile.dart';
import 'viewer_screen.dart';

/// Every PDF on the device in one list, newest first, searchable by name.
class AllPdfsScreen extends StatefulWidget {
  const AllPdfsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const AllPdfsScreen());

  @override
  State<AllPdfsScreen> createState() => _AllPdfsScreenState();
}

class _AllPdfsScreenState extends State<AllPdfsScreen> {
  late Future<List<FoundPdf>> _search = Storage.findAll();
  String _query = '';

  Future<void> _refresh() async {
    final search = Storage.findAll();
    setState(() => _search = search);
    await search;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.allPdfs),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SearchBar(
              hintText: l10n.searchPdfs,
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<FoundPdf>>(
              future: _search,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data ?? const <FoundPdf>[];
                final shown = _query.isEmpty
                    ? all
                    : [
                        for (final pdf in all)
                          if (pdf.name.toLowerCase().contains(_query)) pdf,
                      ];
                if (shown.isEmpty) {
                  return EmptyView(
                    icon: Icons.search_off,
                    title: l10n.noPdfsFoundTitle,
                    body: all.isEmpty ? l10n.noPdfsFoundBody : '',
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, index) {
                      final pdf = shown[index];
                      final entry = PdfEntry.fromPath(pdf.path);
                      return DocumentTile(
                        entry: entry,
                        size: pdf.size,
                        onTap: () => ViewerScreen.open(context, entry),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
