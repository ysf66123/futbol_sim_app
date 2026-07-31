import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../services/match_engine.dart';
import '../utils/dialogs.dart';
import '../utils/game_exception.dart';
import '../widgets/ui.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  final _augmentSearchController = TextEditingController();
  final _playerSearchController = TextEditingController();
  String _augmentSearch = '';
  String _playerSearch = '';
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _augmentSearchController.addListener(() {
      setState(() => _augmentSearch = _augmentSearchController.text.trim());
    });
    _playerSearchController.addListener(() {
      setState(() => _playerSearch = _playerSearchController.text.trim());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _augmentSearchController.dispose();
    _playerSearchController.dispose();
    super.dispose();
  }

  Future<void> _handle(Future<void> Function() action) async {
    try {
      await action();
    } on GameException catch (error) {
      if (!mounted) return;
      await showGameDialog(context, title: error.title, message: error.message);
    } catch (error) {
      if (!mounted) return;
      await showGameDialog(context, title: 'Hata', message: '$error');
    }
  }

  Future<void> _openAugmentEditor(
    BuildContext context,
    SessionController session,
    String augmentId,
    Map<String, dynamic> data,
  ) async {
    final result = await Navigator.of(context).push<_AugmentEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AugmentEditorScreen(
          augmentId: augmentId,
          initialName: data['name'] as String? ?? '',
          initialDescription: data['description'] as String? ?? '',
        ),
      ),
    );
    if (!mounted || result == null) return;

    await _handle(() async {
      await session.saveAugmentCatalogEntry(
        augmentId: augmentId,
        name: result.name,
        description: result.description,
      );
      await session.refreshCatalogData();
    });
  }

  Future<void> _openPlayerEditor(
    BuildContext context,
    SessionController session, {
    Map<String, dynamic>? existing,
  }) async {
    final result = await Navigator.of(context).push<_PlayerEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PlayerEditorScreen(existing: existing),
      ),
    );
    if (!mounted || result == null) return;

    await _handle(() async {
      await session.savePlayerCatalogEntry(
        playerId: result.playerId,
        name: result.name,
        mevki: result.mevki,
        stats: result.stats,
      );
      await session.refreshCatalogData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    if (!session.isAdmin) {
      return GamePageScaffold(
        title: 'Admin Paneli',
        subtitle: 'Bu alan sadece admin hesabina acik.',
        actions: [
          GameIconButton(
            onPressed: () => session.switchView(GameView.lobby),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ],
        child: const Center(
          child: EmptyPanel(message: 'Bu hesabin admin yetkisi yok.'),
        ),
      );
    }

    final augmentEntries =
        session.augmentCatalog.entries
            .where((entry) {
              if (_augmentSearch.isEmpty) return true;
              final haystack =
                  '${entry.key} ${entry.value['name']} ${entry.value['description']}'
                      .toLowerCase();
              return haystack.contains(_augmentSearch.toLowerCase());
            })
            .toList(growable: false)
          ..sort((left, right) => left.key.compareTo(right.key));

    final playerEntries = session.playerCatalog
        .where((player) {
          if (_playerSearch.isEmpty) return true;
          final haystack =
              '${player['id']} ${player['name']} ${player['mevki']}'
                  .toLowerCase();
          return haystack.contains(_playerSearch.toLowerCase());
        })
        .toList(growable: false);

    return GamePageScaffold(
      title: 'Admin Paneli',
      subtitle: 'Eklenti ve oyuncu kataloglarini yonet.',
      actions: [
        GameIconButton(
          onPressed: () => _handle(session.refreshCatalogData),
          icon: const Icon(Icons.refresh_rounded),
        ),
        GameIconButton(
          onPressed: () => session.switchView(GameView.lobby),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Eklentiler'),
                Tab(text: 'Oyuncular'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    children: [
                      TextField(
                        controller: _augmentSearchController,
                        decoration: const InputDecoration(
                          labelText: 'Eklenti ara',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: ListView.separated(
                          itemCount: augmentEntries.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = augmentEntries[index];
                            return SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.value['name'] as String? ?? entry.key,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry.value['description'] as String? ?? '',
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.key,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.white70),
                                        ),
                                      ),
                                      GameOutlinedButton(
                                        onPressed: () => _openAugmentEditor(
                                          context,
                                          session,
                                          entry.key,
                                          entry.value,
                                        ),
                                        child: const Text('Duzenle'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _playerSearchController,
                              decoration: const InputDecoration(
                                labelText: 'Oyuncu ara',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GameFilledButton(
                            onPressed: () =>
                                _openPlayerEditor(context, session),
                            child: const Text('Oyuncu Ekle'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: ListView.separated(
                          itemCount: playerEntries.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final player = playerEntries[index];
                            return SectionCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${player['name']}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${player['mevki']}  |  Rating ${player['rating']}  |  Fiyat ${player['price']}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${player['id']}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GameOutlinedButton(
                                    onPressed: () => _openPlayerEditor(
                                      context,
                                      session,
                                      existing: player,
                                    ),
                                    child: const Text('Duzenle'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AugmentEditorResult {
  _AugmentEditorResult({required this.name, required this.description});

  final String name;
  final String description;
}

class _AugmentEditorScreen extends StatefulWidget {
  const _AugmentEditorScreen({
    required this.augmentId,
    required this.initialName,
    required this.initialDescription,
  });

  final String augmentId;
  final String initialName;
  final String initialDescription;

  @override
  State<_AugmentEditorScreen> createState() => _AugmentEditorScreenState();
}

class _AugmentEditorScreenState extends State<_AugmentEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (!mounted) return;
      Navigator.of(context).pop(
        _AugmentEditorResult(
          name: _nameController.text,
          description: _descriptionController.text,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GamePageScaffold(
      title: 'Eklenti Duzenle',
      subtitle: widget.augmentId,
      actions: [
        GameIconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Aciklama'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GameFilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerEditorResult {
  _PlayerEditorResult({
    required this.playerId,
    required this.name,
    required this.mevki,
    required this.stats,
  });

  final String? playerId;
  final String name;
  final String mevki;
  final Map<String, dynamic> stats;
}

class _PlayerEditorScreen extends StatefulWidget {
  const _PlayerEditorScreen({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_PlayerEditorScreen> createState() => _PlayerEditorScreenState();
}

class _PlayerEditorScreenState extends State<_PlayerEditorScreen> {
  late final TextEditingController _nameController;
  late final Map<String, TextEditingController> _statControllers;
  late String _mevki;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    _mevki = existing?['mevki'] as String? ?? 'Orta Saha';
    _statControllers = {
      for (final key in const [
        'hucum',
        'savunma',
        'dayaniklilik',
        'sut',
        'pas',
        'hiz',
      ])
        key: TextEditingController(
          text:
              ((existing?['stats'] as Map?)?[key] as num?)
                  ?.toInt()
                  .toString() ??
              '',
        ),
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _statControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _currentStats() {
    return {
      for (final entry in _statControllers.entries)
        entry.key: int.tryParse(entry.value.text.trim()) ?? 0,
    };
  }

  void _applyRandomProfile() {
    final session = context.read<SessionController>();
    final profile = session.buildRandomPlayerProfile(mevki: _mevki);
    final stats =
        (profile['stats'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    for (final entry in _statControllers.entries) {
      entry.value.text = ((stats[entry.key] as num?)?.toInt() ?? 0).toString();
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (!mounted) return;
      Navigator.of(context).pop(
        _PlayerEditorResult(
          playerId: widget.existing?['id'] as String?,
          name: _nameController.text,
          mevki: _mevki,
          stats: _currentStats(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _statField(String key, String label) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: _statControllers[key],
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _currentStats();
    final rating = calculateRating(stats, _mevki);
    final price = calculatePrice(rating);

    return GamePageScaffold(
      title: widget.existing == null ? 'Oyuncu Ekle' : 'Oyuncu Duzenle',
      subtitle: widget.existing == null
          ? 'Yeni kayit'
          : '${widget.existing?['id']}',
      actions: [
        GameIconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Ad'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _mevki,
                  items: const [
                    DropdownMenuItem(value: 'Kaleci', child: Text('Kaleci')),
                    DropdownMenuItem(value: 'Defans', child: Text('Defans')),
                    DropdownMenuItem(
                      value: 'Orta Saha',
                      child: Text('Orta Saha'),
                    ),
                    DropdownMenuItem(value: 'Forvet', child: Text('Forvet')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _mevki = value);
                  },
                  decoration: const InputDecoration(labelText: 'Mevki'),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _statField('hucum', 'Hucum'),
                    _statField('savunma', 'Savunma'),
                    _statField('dayaniklilik', 'Dayaniklilik'),
                    _statField('sut', 'Sut'),
                    _statField('pas', 'Pas'),
                    _statField('hiz', 'Hiz'),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    InfoBadge(label: 'Rating $rating'),
                    InfoBadge(label: 'Fiyat $price'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GameOutlinedButton(
                        onPressed: _saving ? null : _applyRandomProfile,
                        child: const Text('Rastgele Doldur'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GameFilledButton(
                        onPressed: _saving ? null : _submit,
                        child: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
