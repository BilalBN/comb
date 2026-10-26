import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/controller.dart';
import '../../core/api.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../security/app_lock.dart';
import '../theme.dart';
import '../widgets.dart';
import '../detail/fields.dart';

enum SettingsTab { appearance, spaces, security, devices, sync, about }

extension on SettingsTab {
  String get label => switch (this) {
    SettingsTab.appearance => 'Look and feel',
    SettingsTab.spaces => 'Spaces',
    SettingsTab.security => 'App lock',
    SettingsTab.devices => 'Devices',
    SettingsTab.sync => 'Sync and folder',
    SettingsTab.about => 'About',
  };
  IconData get icon => switch (this) {
    SettingsTab.appearance => Icons.palette_outlined,
    SettingsTab.spaces => Icons.hexagon_outlined,
    SettingsTab.security => Icons.lock_outline,
    SettingsTab.devices => Icons.devices_outlined,
    SettingsTab.sync => Icons.sync,
    SettingsTab.about => Icons.info_outline,
  };
}

Future<void> showSettings(BuildContext context, AppController c, {SettingsTab tab = SettingsTab.appearance}) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: SettingsScreen(c: c, initial: tab),
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.c, this.initial = SettingsTab.appearance});
  final AppController c;
  final SettingsTab initial;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsTab tab = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return ListenableBuilder(
      listenable: widget.c,
      builder: (context, _) {
        if (widget.c.library == null) return const SizedBox.shrink();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 210,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.side,
                border: Border(right: BorderSide(color: t.line)),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                    child: Text('Settings', style: t.heading),
                  ),
                  for (final s in SettingsTab.values)
                    Material(
                      color: s == tab ? t.accentTint : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        leading: Icon(s.icon, size: 18, color: s == tab ? t.accent : t.sub),
                        title: Text(
                          s.label,
                          style: t.text(14, weight: s == tab ? FontWeight.w600 : FontWeight.w400, color: s == tab ? t.accent : t.ink),
                        ),
                        onTap: () => setState(() => tab = s),
                      ),
                    ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(28),
                children: [
                  Text(tab.label, style: t.title),
                  const SizedBox(height: 20),
                  switch (tab) {
                    SettingsTab.appearance => _Appearance(c: widget.c),
                    SettingsTab.spaces => _Spaces(c: widget.c),
                    SettingsTab.security => _Security(c: widget.c),
                    SettingsTab.devices => _Devices(c: widget.c),
                    SettingsTab.sync => _Sync(c: widget.c),
                    SettingsTab.about => _About(c: widget.c),
                  },
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

Widget _section(BuildContext context, String title, List<Widget> children, {String? note}) {
  final t = context.comb;
  return Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.text(14, weight: FontWeight.w600)),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(note, style: t.small),
          ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

// ---------------------------------------------------------------- appearance

class _Appearance extends StatelessWidget {
  const _Appearance({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final p = c.prefs;
    final lib = c.library!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'Theme', [
          Segmented<ThemeMode>(
            values: const [ThemeMode.light, ThemeMode.dark, ThemeMode.system],
            selected: p.themeMode,
            label: (m) => switch (m) {
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
              _ => 'Auto',
            },
            onChanged: (m) {
              p.themeMode = m;
              c.savePrefs();
            },
          ),
        ]),
        _section(context, 'Accent colour', [
          Wrap(
            spacing: 12,
            children: [
              for (final a in Accent.values)
                Tooltip(
                  message: a.label,
                  child: Semantics(
                    button: true,
                    selected: p.accent == a,
                    label: a.label,
                    child: InkResponse(
                      onTap: () {
                        p.accent = a;
                        c.savePrefs();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: CombTokens.of(dark: t.dark, accent: a, density: p.density, font: p.font).accent,
                          border: Border.all(color: p.accent == a ? t.ink : Colors.transparent, width: 2.5),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ]),
        _section(context, 'Density', [
          Segmented<Density>(
            values: Density.values,
            selected: p.density,
            label: (d) => d == Density.compact ? 'Compact' : 'Comfortable',
            onChanged: (d) {
              p.density = d;
              c.savePrefs();
            },
          ),
        ]),
        _section(context, 'Font', [
          Segmented<FontChoice>(
            values: FontChoice.values,
            selected: p.font,
            label: (f) => f == FontChoice.inter ? 'Inter' : 'System',
            onChanged: (f) {
              p.font = f;
              c.savePrefs();
            },
          ),
        ]),
        _section(context, 'Matrix', [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              Text('A task counts as urgent when it is due within', style: t.body),
              DropdownButton<int>(
                value: lib.settings.urgentWithinDays,
                items: [
                  for (final d in [0, 1, 2, 3, 5, 7])
                    DropdownMenuItem(value: d, child: Text(d == 0 ? 'today' : '$d day${d == 1 ? '' : 's'}')),
                ],
                onChanged: (d) {
                  lib.settings.urgentWithinDays = d!;
                  c.edit((l) => l.saveSettings());
                },
              ),
            ],
          ),
        ], note: 'Shared by all your devices. You can always mark a task urgent or not urgent by hand.'),
      ],
    );
  }
}

// ---------------------------------------------------------------- spaces

class _Spaces extends StatefulWidget {
  const _Spaces({required this.c});
  final AppController c;
  @override
  State<_Spaces> createState() => _SpacesState();
}

class _SpacesState extends State<_Spaces> {
  final _newName = TextEditingController();
  Space? _newParent;
  String? _openId;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final c = widget.c;
    final lib = c.library!;
    final rows = <(Space, int)>[];
    void walk(Space? parent, int depth) {
      for (final s in lib.children(parent)) {
        rows.add((s, depth));
        walk(s, depth + 1);
      }
    }

    walk(null, 0);
    final archived = lib.spaces.where((s) => s.archived).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Spaces keep work, home and business apart. Each can have its own colour, categories and email. Put a Space inside another to group them; notes move with it.',
          style: t.text(13, color: t.sub),
        ),
        const SizedBox(height: 16),
        for (final (s, depth) in rows) _row(context, s, depth),
        const SizedBox(height: 16),
        _section(context, 'Add a Space', [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newName,
                  decoration: const InputDecoration(hintText: 'Name, e.g. Crypt4Bits'),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: SpacePicker(lib: lib, value: _newParent, onChanged: (s) => setState(() => _newParent = s)),
              ),
              const SizedBox(width: 8),
              PrimaryButton(
                label: 'Add',
                onPressed: () {
                  if (_newName.text.trim().isEmpty) return;
                  c.edit((l) => l.addSpace(_newName.text, parent: _newParent));
                  _newName.clear();
                  setState(() => _newParent = null);
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Pick a Space on the right to put the new one inside it, or leave "No Space" for a top-level one.', style: t.small),
          ),
        ]),
        if (archived.isNotEmpty)
          _section(context, 'Archived', [
            for (final s in archived)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SpaceDot(s.color),
                title: Text(s.name, style: t.body),
                trailing: TextButton(onPressed: () => c.edit((l) => l.archiveSpace(s, archived: false)), child: const Text('Restore')),
              ),
          ]),
      ],
    );
  }

  Widget _row(BuildContext context, Space s, int depth) {
    final t = context.comb;
    final c = widget.c;
    final lib = c.library!;
    final open = _openId == s.id;
    return Padding(
      padding: EdgeInsets.only(left: depth * 24.0, bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: open ? t.accent : t.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: PopupMenuButton<String>(
                tooltip: 'Colour',
                onSelected: (col) => c.edit((l) => l.updateSpace(s, color: col)),
                itemBuilder: (_) => [
                  for (final col in spaceColors)
                    PopupMenuItem(
                      value: col,
                      child: Row(children: [SpaceDot(col, size: 12), const SizedBox(width: 10), Text(col)]),
                    ),
                ],
                child: Padding(padding: const EdgeInsets.all(8), child: SpaceDot(s.color, size: 14)),
              ),
              title: Text(s.name, style: t.bodyStrong),
              subtitle: Text(
                [
                  if (s.categories.isNotEmpty) s.categories.join(', '),
                  if (s.email != null) s.email!,
                  '${c.views.openCount(s)} open tasks',
                ].join(' · '),
                style: t.small,
              ),
              trailing: Icon(open ? Icons.expand_less : Icons.expand_more, color: t.sub),
              onTap: () => setState(() => _openId = open ? null : s.id),
            ),
            if (open) _SpaceEditor(key: ValueKey(s.id), c: c, s: s, lib: lib),
          ],
        ),
      ),
    );
  }
}

class _SpaceEditor extends StatefulWidget {
  const _SpaceEditor({super.key, required this.c, required this.s, required this.lib});
  final AppController c;
  final Space s;
  final Library lib;
  @override
  State<_SpaceEditor> createState() => _SpaceEditorState();
}

class _SpaceEditorState extends State<_SpaceEditor> {
  late final _name = TextEditingController(text: widget.s.name);
  late final _cats = TextEditingController(text: widget.s.categories.join(', '));
  late final _email = TextEditingController(text: widget.s.email ?? '');
  String? _error;

  void _save() {
    try {
      widget.c.edit(
        (l) => l.updateSpace(
          widget.s,
          name: _name.text,
          categories: _cats.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
          email: _email.text.trim(),
        ),
      );
      setState(() => _error = null);
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final s = widget.s;
    final lib = widget.lib;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldRow(
            label: 'Name',
            child: TextField(controller: _name, onSubmitted: (_) => _save()),
          ),
          FieldRow(
            label: 'Categories',
            child: TextField(
              controller: _cats,
              decoration: const InputDecoration(hintText: 'Client, Internal, Sales'),
              onSubmitted: (_) => _save(),
            ),
          ),
          FieldRow(
            label: 'Email',
            child: TextField(
              controller: _email,
              decoration: const InputDecoration(hintText: 'Used for reminders and digests (M3)'),
              onSubmitted: (_) => _save(),
            ),
          ),
          FieldRow(
            label: 'Inside',
            child: SpacePicker(
              lib: lib,
              value: lib.spaceById(s.parentId),
              onChanged: (p) {
                try {
                  widget.c.edit((l) => l.updateSpace(s, parent: p));
                  setState(() => _error = null);
                } on ArgumentError catch (e) {
                  setState(() => _error = '${e.message}');
                }
              },
            ),
          ),
          if (_error != null) Text(_error!, style: t.text(13, color: t.urgentInk)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PrimaryButton(label: 'Save', onPressed: _save),
              QuietButton(label: 'Archive', onPressed: () => widget.c.edit((l) => l.archiveSpace(s))),
              Text('Renaming or moving updates every task and note in it.', style: t.small),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- security

class _Security extends StatefulWidget {
  const _Security({required this.c});
  final AppController c;
  @override
  State<_Security> createState() => _SecurityState();
}

class _SecurityState extends State<_Security> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _next2 = TextEditingController();
  final _reveal = TextEditingController();
  String? _msg;
  String? _recovery;
  bool _busy = false;
  bool? _bioAvailable;

  @override
  void initState() {
    super.initState();
    widget.c.biometricsAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final c = widget.c;
    final s = c.lock.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'How Comb locks', [
          Text(
            'After this device restarts, Comb asks for your password${s.biometrics ? ' and fingerprint' : ''}. In between, ${s.biometrics ? 'your fingerprint' : 'the cached unlock'} opens it.',
            style: t.text(13, color: t.sub),
          ),
          const SizedBox(height: 12),
          if (_bioAvailable == true)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.biometrics,
              title: Text('Use fingerprint', style: t.body),
              subtitle: Text('Touch ID on Mac, fingerprint on Android', style: t.small),
              onChanged: (v) async {
                await c.lock.updatePreferences(useBiometrics: v);
                setState(() {});
              },
            ),
          if (_bioAvailable == false) Text('No fingerprint reader found on this device.', style: t.small),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text('Lock again', style: t.body),
              DropdownButton<RelockAfter>(
                value: s.relock,
                items: [for (final r in RelockAfter.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (r) async {
                  await c.lock.updatePreferences(relock: r);
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          QuietButton(
            label: 'Lock now',
            icon: Icons.lock_outline,
            onPressed: () {
              Navigator.of(context).pop();
              c.lockNow();
            },
          ),
        ]),
        _section(context, 'Change password', [
          SizedBox(
            width: 360,
            child: TextField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 360,
            child: TextField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 360,
            child: TextField(
              controller: _next2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password again'),
            ),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Change password',
            busy: _busy,
            onPressed: () async {
              if (_next.text != _next2.text) return setState(() => _msg = 'The new passwords are different.');
              setState(() => _busy = true);
              try {
                await c.changePassword(_current.text, _next.text);
                _current.clear();
                _next.clear();
                _next2.clear();
                setState(() => _msg = 'Password changed.');
              } on WrongPassword {
                setState(() => _msg = 'The current password is not right.');
              } on ArgumentError catch (e) {
                setState(() => _msg = '${e.message}');
              } finally {
                setState(() => _busy = false);
              }
            },
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_msg!, style: t.small),
            ),
        ], note: 'Changing it here changes it on this device only. Each device has its own app password.'),
        _section(context, 'Recovery key', [
          if (_recovery == null) ...[
            SizedBox(
              width: 360,
              child: TextField(
                controller: _reveal,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password, to show the key'),
              ),
            ),
            const SizedBox(height: 8),
            QuietButton(
              label: 'Show recovery key',
              onPressed: () async {
                try {
                  await c.lock.verifyPassword(_reveal.text);
                  setState(() => _recovery = c.revealRecoveryKey());
                } on WrongPassword {
                  setState(() => _msg = 'That password is not right.');
                }
              },
            ),
          ] else
            SelectableText(
              _recovery!,
              style: t.text(15, weight: FontWeight.w500).copyWith(fontFamily: 'Menlo', letterSpacing: 1),
            ),
        ], note: 'The only way back in if every device is lost. Keep it offline.'),
      ],
    );
  }
}

// ---------------------------------------------------------------- devices

class _Devices extends StatefulWidget {
  const _Devices({required this.c});
  final AppController c;
  @override
  State<_Devices> createState() => _DevicesState();
}

class _DevicesState extends State<_Devices> {
  late Future<List<RemoteDevice>> _list = widget.c.devices();
  ({String link, DateTime expires})? _pair;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final c = widget.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'Signed-in devices', [
          FutureBuilder<List<RemoteDevice>>(
            future: _list,
            builder: (context, snap) {
              if (snap.hasError) return Text('Could not load the device list: ${snap.error}', style: t.small);
              if (!snap.hasData) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              final list = snap.data!.where((d) => !d.revoked).toList();
              return Column(
                children: [
                  for (final d in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.devices_outlined, color: t.sub),
                      title: Text(d.name + (d.thisDevice ? ' (this device)' : ''), style: t.body),
                      subtitle: Text(d.lastSeen == null ? 'Not seen yet' : 'Last seen ${_ago(d.lastSeen!)}', style: t.small),
                      trailing: d.thisDevice
                          ? null
                          : TextButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('Remove ${d.name}?'),
                                    content: const Text('It is signed out at once and can no longer sync.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await c.removeDevice(d.id);
                                  setState(() => _list = c.devices());
                                }
                              },
                              child: const Text('Remove'),
                            ),
                    ),
                ],
              );
            },
          ),
        ]),
        _section(context, 'Add a device', [
          if (_pair == null) ...[
            PrimaryButton(
              label: 'Show pairing code',
              icon: Icons.qr_code,
              onPressed: () async {
                try {
                  final p = await c.startPairing();
                  setState(() {
                    _pair = p;
                    _error = null;
                  });
                } on ApiException catch (e) {
                  setState(() => _error = e.message);
                }
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: t.text(13, color: t.urgentInk)),
              ),
          ] else ...[
            Text(
              'On the new device, choose Add this device and scan this code, or paste the link. It works once, for 10 minutes.',
              style: t.text(13, color: t.sub),
            ),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: _pair!.link, size: 220, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                QuietButton(
                  label: 'Copy link',
                  icon: Icons.copy,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _pair!.link));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pairing link copied. It contains your recovery key: paste it only on your own device.'),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _pair = null;
                    _list = c.devices();
                  }),
                  child: const Text('Done'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This code contains your encryption key. Show it only to your own devices; never send it in a message.',
              style: t.text(12, color: t.urgentInk),
            ),
          ],
        ]),
      ],
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${diff.inDays} days ago';
  }
}

// ---------------------------------------------------------------- sync and folder

class _Sync extends StatelessWidget {
  const _Sync({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final conn = c.connection;
    final last = c.engine?.state.lastSync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'Server', [
          FieldRow(
            label: 'Address',
            child: SelectableText(conn?.serverUrl ?? '', style: t.body),
          ),
          FieldRow(
            label: 'This device',
            child: Text(conn?.deviceName ?? '', style: t.body),
          ),
          FieldRow(
            label: 'Status',
            child: Text(c.syncLabel, style: t.body),
          ),
          FieldRow(
            label: 'Last sync',
            child: Text(last == null ? 'Not yet' : TimeOfDay.fromDateTime(last).format(context), style: t.body),
          ),
          FieldRow(
            label: 'Waiting',
            child: Text('${c.engine?.state.outbox.length ?? 0} changes to send', style: t.body),
          ),
          const SizedBox(height: 8),
          QuietButton(label: 'Sync now', icon: Icons.sync, onPressed: c.syncNow),
        ], note: 'Everything is encrypted on this device before it is sent. The server cannot read it.'),
        _section(
          context,
          'Markdown folder',
          [
            Text(c.prefs.folderPath ?? 'Not set', style: t.body),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                QuietButton(
                  label: c.prefs.folderPath == null ? 'Choose folder' : 'Change folder',
                  icon: Icons.folder_outlined,
                  onPressed: () async {
                    final path = await getDirectoryPath(confirmButtonText: 'Use this folder');
                    if (path != null) await c.chooseFolder(path);
                  },
                ),
                if (c.prefs.folderPath != null) QuietButton(label: 'Stop using a folder', onPressed: () => c.chooseFolder(null)),
              ],
            ),
          ],
          note: 'Every note and task as a plain markdown file, for Obsidian or any editor. Edits there come back into Comb. Files in this folder are not encrypted, so keep it on this computer (not in a shared cloud folder) if that matters to you.',
        ),
        _section(context, 'Export', [
          QuietButton(
            label: 'Export tasks (CSV) and everything (JSON)',
            icon: Icons.download_outlined,
            onPressed: () async {
              final folder = await getDirectoryPath(confirmButtonText: 'Export here');
              if (folder == null) return;
              final files = await c.exportTo(folder);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported ${files.length} files to $folder')));
              }
            },
          ),
        ], note: 'Readable copies for spreadsheets or other apps. They are not encrypted.'),
      ],
    );
  }
}

// ---------------------------------------------------------------- about

class _About extends StatelessWidget {
  const _About({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comb 0.1 (M1)', style: t.bodyStrong),
        const SizedBox(height: 4),
        Text('Open source, MIT licence. Inter font under the SIL Open Font Licence.', style: t.small),
        const SizedBox(height: 16),
        _section(context, 'Keyboard', [
          for (final (k, v) in const [
            ('⌘N', 'Add a task'),
            ('⇧⌘N', 'New note'),
            ('⌘F', 'Search'),
            ('⌘1 … ⌘4', 'Today, Matrix, Board, Notes'),
            ('⌘↩', 'In a note: make a task from this line'),
            ('⌘L', 'Lock'),
            ('Esc', 'Close the task panel'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(width: 110, child: Text(k, style: t.bodyStrong)),
                  Expanded(child: Text(v, style: t.body)),
                ],
              ),
            ),
        ]),
        _section(context, 'Forget this device', [
          Text(
            'Signs this device out and deletes its copy of your notes. Your other devices, the server and the markdown folder are not touched.',
            style: t.text(13, color: t.sub),
          ),
          const SizedBox(height: 10),
          QuietButton(
            label: 'Forget this device',
            danger: true,
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Forget this device?'),
                  content: const Text('You can add it again later with the recovery key or a pairing code.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Forget')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                Navigator.of(context).pop();
                await c.forgetThisDevice();
              }
            },
          ),
        ]),
      ],
    );
  }
}
