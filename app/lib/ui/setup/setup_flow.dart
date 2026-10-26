import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../core/api.dart';
import '../../data/library.dart';
import '../brand.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Step { welcome, server, create, join, recovery, password, folder, spaces }

class SetupFlow extends StatefulWidget {
  const SetupFlow({super.key, required this.controller});
  final AppController controller;

  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SpaceDraft {
  _SpaceDraft(this.name, this.color, {this.parent});
  final TextEditingController name;
  String color;
  _SpaceDraft? parent;
}

class _SetupFlowState extends State<SetupFlow> {
  AppController get c => widget.controller;

  _Step step = _Step.welcome;
  bool busy = false;
  String? error;
  bool joining = false;

  final server = TextEditingController(text: 'http://127.0.0.1:8080');
  final setupCode = TextEditingController();
  final deviceName = TextEditingController(text: _defaultDeviceName());
  final pairLink = TextEditingController();
  final pairCode = TextEditingController();
  final pairKey = TextEditingController();
  final password = TextEditingController();
  final password2 = TextEditingController();
  bool savedRecovery = false;
  bool useBiometrics = true;
  bool biometricsAvailable = false;
  String? folder;

  late final List<_SpaceDraft> spaces = [
    _SpaceDraft(TextEditingController(text: 'Personal'), 'green'),
    _SpaceDraft(TextEditingController(text: 'Work'), 'blue'),
  ];

  static String _defaultDeviceName() {
    try {
      final host = Platform.localHostname.replaceAll(RegExp(r'\.local$'), '').replaceAll('-', ' ').trim();
      if (host.isNotEmpty) return host;
    } catch (_) {}
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isAndroid) return 'Android phone';
    if (Platform.isIOS) return 'iPhone';
    return 'Computer';
  }

  bool get _desktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    } on ArgumentError catch (e) {
      setState(() => error = '${e.message}');
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _go(_Step s) => setState(() {
    step = s;
    error = null;
  });

  Future<void> _checkServer() => _run(() async {
    final url = server.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw const FormatException('Start the address with https:// (or http:// for this computer).');
    }
    await c.checkServer(url);
    final fresh = await c.serverIsNew(url);
    joining = !fresh;
    _go(fresh ? _Step.create : _Step.join);
  });

  Future<void> _create() => _run(() async {
    if (setupCode.text.trim().isEmpty) throw const FormatException('Enter the setup code the server printed.');
    await c.createAccount(serverUrl: server.text.trim(), setupCode: setupCode.text, deviceName: deviceName.text);
    _go(_Step.recovery);
  });

  Future<void> _join() => _run(() async {
    if (pairLink.text.trim().isNotEmpty) {
      await c.joinWithLink(link: pairLink.text, deviceName: deviceName.text);
    } else {
      if (pairCode.text.trim().isEmpty || pairKey.text.trim().isEmpty) {
        throw const FormatException('Paste the pairing link, or enter the code and recovery key.');
      }
      await c.joinWithCode(serverUrl: server.text.trim(), code: pairCode.text, recoveryKey: pairKey.text, deviceName: deviceName.text);
    }
    biometricsAvailable = await c.biometricsAvailable();
    _go(_Step.password);
  });

  Future<void> _toPassword() async {
    biometricsAvailable = await c.biometricsAvailable();
    _go(_Step.password);
  }

  Future<void> _setPassword() => _run(() async {
    if (password.text.length < 6) throw const FormatException('Use at least 6 characters.');
    if (password.text != password2.text) throw const FormatException('The two passwords are different.');
    await c.setupPassword(password.text, useBiometrics: biometricsAvailable && useBiometrics);
    if (_desktop) {
      _go(_Step.folder);
    } else {
      await _open();
    }
  });

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (path != null) setState(() => folder = path);
  }

  Future<void> _open() => _run(() async {
    await c.chooseFolder(folder);
    await c.finishSetupOpen();
    if (joining) {
      await c.syncNow();
      c.completeSetup();
    } else {
      _go(_Step.spaces);
    }
  });

  Future<void> _makeSpaces() => _run(() async {
    final lib = c.library!;
    final made = <_SpaceDraft, dynamic>{};
    for (final d in spaces.where((d) => d.parent == null)) {
      if (d.name.text.trim().isEmpty) continue;
      made[d] = lib.addSpace(d.name.text, color: d.color);
    }
    for (final d in spaces.where((d) => d.parent != null)) {
      if (d.name.text.trim().isEmpty || made[d.parent] == null) continue;
      made[d] = lib.addSpace(d.name.text, color: d.color, parent: made[d.parent]);
    }
    await c.syncNow();
    c.completeSetup();
  });

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(children: [CombMark(size: 26), SizedBox(width: 10)]),
                  const SizedBox(height: 20),
                  ..._body(context),
                  if (error != null) ...[const SizedBox(height: 12), Text(error!, style: t.text(13, color: t.urgentInk))],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final t = context.comb;
    Widget h(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(s, style: t.title),
    );
    Widget p(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(s, style: t.text(14, color: t.sub)),
    );
    const gap = SizedBox(height: 12);

    switch (step) {
      case _Step.welcome:
        return [
          h('Welcome to Comb'),
          p('Notes and tasks for work, home and your own business, in one place.'),
          _point(Icons.lock_outline, 'End-to-end encrypted', 'Only your devices can read your notes. The server stores scrambled data.'),
          _point(
            Icons.description_outlined,
            'Plain files you own',
            'Everything can be kept as markdown files on this computer, ready for Obsidian.',
          ),
          _point(Icons.grid_view_outlined, 'Yours to shape', 'Your own Spaces, categories, priorities and look.'),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: PrimaryButton(label: 'Set up Comb', onPressed: () => _go(_Step.server)),
          ),
        ];

      case _Step.server:
        return [
          h('Your Comb server'),
          p(
            'The address of the server that syncs your devices. While testing on this Mac it is the one running in your Comb-Project folder.',
          ),
          TextField(
            controller: server,
            decoration: const InputDecoration(labelText: 'Server address'),
            autofocus: true,
            onSubmitted: (_) => _checkServer(),
          ),
          gap,
          Row(
            children: [
              PrimaryButton(label: 'Continue', onPressed: _checkServer, busy: busy),
              const SizedBox(width: 8),
              TextButton(onPressed: () => _go(_Step.welcome), child: const Text('Back')),
            ],
          ),
        ];

      case _Step.create:
        return [
          h('Set up this server'),
          p(
            'This server has no account yet. Enter the one-time setup code it printed when it first started (also in its data folder, in SETUP_CODE.txt).',
          ),
          TextField(
            controller: setupCode,
            decoration: const InputDecoration(labelText: 'Setup code', hintText: 'ABCDE-FGHJK'),
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
          ),
          gap,
          TextField(
            controller: deviceName,
            decoration: const InputDecoration(labelText: 'Name for this device'),
          ),
          gap,
          Row(
            children: [
              PrimaryButton(label: 'Create account', onPressed: _create, busy: busy),
              const SizedBox(width: 8),
              TextButton(onPressed: () => _go(_Step.server), child: const Text('Back')),
            ],
          ),
        ];

      case _Step.join:
        return [
          h('Add this device'),
          p(
            'This server already has an account. On a device that is already set up, open Settings, Devices, Add a device, and paste the link it shows (or type the code and recovery key).',
          ),
          TextField(
            controller: pairLink,
            decoration: const InputDecoration(labelText: 'Pairing link', hintText: 'comb://pair?…'),
            maxLines: 2,
            minLines: 1,
          ),
          gap,
          Text('or', style: t.small, textAlign: TextAlign.center),
          gap,
          TextField(
            controller: pairCode,
            decoration: const InputDecoration(labelText: 'Pairing code'),
            textCapitalization: TextCapitalization.characters,
          ),
          gap,
          TextField(
            controller: pairKey,
            decoration: const InputDecoration(labelText: 'Recovery key'),
            textCapitalization: TextCapitalization.characters,
          ),
          gap,
          TextField(
            controller: deviceName,
            decoration: const InputDecoration(labelText: 'Name for this device'),
          ),
          gap,
          Row(
            children: [
              PrimaryButton(label: 'Add device', onPressed: _join, busy: busy),
              const SizedBox(width: 8),
              TextButton(onPressed: () => _go(_Step.server), child: const Text('Back')),
            ],
          ),
        ];

      case _Step.recovery:
        final key = c.setupRecoveryKey ?? '';
        return [
          h('Save your recovery key'),
          p(
            'This key is the only way back in if every device is lost or you forget your password. Nobody else has it, not even the server. Write it down or keep it in a password manager.',
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.side,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.line),
            ),
            child: SelectableText(
              key,
              style: t.text(16, weight: FontWeight.w500).copyWith(fontFamily: 'Menlo', letterSpacing: 1),
            ),
          ),
          gap,
          Align(
            alignment: Alignment.centerLeft,
            child: QuietButton(
              label: 'Copy',
              icon: Icons.copy,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: key));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recovery key copied')));
              },
            ),
          ),
          gap,
          CheckboxListTile(
            value: savedRecovery,
            onChanged: (v) => setState(() => savedRecovery = v ?? false),
            title: Text('I have saved it somewhere safe', style: t.body),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          gap,
          Align(
            alignment: Alignment.centerLeft,
            child: PrimaryButton(label: 'Continue', onPressed: savedRecovery ? _toPassword : null),
          ),
        ];

      case _Step.password:
        return [
          h('Choose an app password'),
          p('You enter it after this device restarts. The rest of the time your fingerprint unlocks Comb.'),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password (at least 6 characters)'),
            autofocus: true,
          ),
          gap,
          TextField(
            controller: password2,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Type it again'),
            onSubmitted: (_) => _setPassword(),
          ),
          if (biometricsAvailable)
            SwitchListTile(
              value: useBiometrics,
              onChanged: (v) => setState(() => useBiometrics = v),
              title: Text('Unlock with fingerprint', style: t.body),
              subtitle: Text('Touch ID on Mac, fingerprint on Android', style: t.small),
              contentPadding: EdgeInsets.zero,
            ),
          gap,
          Align(
            alignment: Alignment.centerLeft,
            child: PrimaryButton(label: 'Continue', onPressed: _setPassword, busy: busy),
          ),
        ];

      case _Step.folder:
        return [
          h('Keep a markdown folder?'),
          p(
            'Comb can keep every note and task as a plain markdown file in a folder on this computer. Open it in Obsidian for the graph view, and edits there come back into Comb. The files in that folder are not encrypted.',
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.line),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, color: t.sub),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(folder ?? 'No folder chosen', style: t.body, overflow: TextOverflow.ellipsis),
                ),
                QuietButton(label: folder == null ? 'Choose folder' : 'Change', onPressed: _pickFolder),
              ],
            ),
          ),
          gap,
          Text('Tip: make a new empty folder for Comb, for example Comb Vault in your Documents.', style: t.small),
          const SizedBox(height: 18),
          Row(
            children: [PrimaryButton(label: folder == null ? 'Skip for now' : 'Continue', onPressed: _open, busy: busy)],
          ),
        ];

      case _Step.spaces:
        return [
          h('Your Spaces'),
          p(
            'Spaces keep work, home and business apart. Rename them, add your own, or put one inside another (for example a brand inside your company). You can change all of this later.',
          ),
          for (final d in spaces) _spaceRow(d),
          gap,
          Align(
            alignment: Alignment.centerLeft,
            child: QuietButton(
              label: 'Add a Space',
              icon: Icons.add,
              onPressed: () =>
                  setState(() => spaces.add(_SpaceDraft(TextEditingController(), spaceColors[spaces.length % spaceColors.length]))),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: PrimaryButton(label: 'Start using Comb', onPressed: _makeSpaces, busy: busy),
          ),
        ];
    }
  }

  Widget _spaceRow(_SpaceDraft d) {
    final t = context.comb;
    final indent = d.parent == null ? 0.0 : 28.0;
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Change colour',
            child: InkResponse(
              onTap: () => setState(() => d.color = spaceColors[(spaceColors.indexOf(d.color) + 1) % spaceColors.length]),
              child: Padding(padding: const EdgeInsets.all(12), child: SpaceDot(d.color, size: 14)),
            ),
          ),
          Expanded(
            child: TextField(
              controller: d.name,
              decoration: InputDecoration(hintText: d.parent == null ? 'Space name' : 'Inside ${d.parent!.name.text}'),
            ),
          ),
          if (d.parent == null)
            IconButton(
              tooltip: 'Add a Space inside this one',
              icon: Icon(Icons.subdirectory_arrow_right, color: t.sub),
              onPressed: () => setState(() {
                final i = spaces.lastIndexWhere((s) => s == d || s.parent == d);
                spaces.insert(i + 1, _SpaceDraft(TextEditingController(), d.color, parent: d));
              }),
            ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close, color: t.sub),
            onPressed: () => setState(() => spaces.removeWhere((s) => s == d || s.parent == d)),
          ),
        ],
      ),
    );
  }

  Widget _point(IconData icon, String title, String text) {
    final t = context.comb;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: t.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.bodyStrong),
                Text(text, style: t.text(13, color: t.sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
