import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../security/app_lock.dart';
import 'brand.dart';
import 'theme.dart';
import 'widgets.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (c.quickUnlockAvailable) WidgetsBinding.instance.addPostFrameCallback((_) => _quick());
  }

  Future<void> _quick() async {
    setState(() => _busy = true);
    final ok = await c.unlockQuick();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = null;
    });
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your app password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await c.unlockWithPassword(_password.text);
    } on WrongPassword catch (e) {
      setState(() => _error = e.toString());
    } on BiometricsFailed catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'Could not unlock: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: CombMark(size: 40)),
                const SizedBox(height: 16),
                Text('Comb is locked', style: t.heading, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                  c.quickUnlockAvailable
                      ? 'Use your fingerprint, or enter your password.'
                      : 'Enter your password. It is needed after the device restarts.',
                  style: t.small,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: !c.quickUnlockAvailable,
                  decoration: InputDecoration(labelText: 'App password', errorText: _error),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                PrimaryButton(label: 'Unlock', onPressed: _submit, busy: _busy),
                if (c.quickUnlockAvailable) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : _quick,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use fingerprint'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
