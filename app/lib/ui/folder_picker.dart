import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../sync/folder_check.dart';
import 'theme.dart';

/// Asks for a markdown folder and checks it before handing it back:
/// unwritable or very slow folders are refused, cloud folders and folders
/// that already hold files need a second "use it anyway".
Future<String?> pickMarkdownFolder(
  BuildContext context, {
  Future<String?> Function()? choose,
  Future<FolderCheck> Function(String)? check,
}) async {
  final path = await (choose ?? () => getDirectoryPath(confirmButtonText: 'Use this folder'))();
  if (path == null || !context.mounted) return null;
  final result = await showDialog<FolderCheck>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Checking(path: path, check: check ?? checkFolder),
  );
  if (result == null || !context.mounted) return null;
  final blocker = result.blocker;
  if (blocker != null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose another folder'),
        content: Text(blocker),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return null;
  }
  if (result.warnings.isEmpty) return path;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Use this folder?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final w in result.warnings) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(w))],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Choose another')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use it anyway')),
      ],
    ),
  );
  return ok == true ? path : null;
}

class _Checking extends StatefulWidget {
  const _Checking({required this.path, required this.check});
  final String path;
  final Future<FolderCheck> Function(String) check;

  @override
  State<_Checking> createState() => _CheckingState();
}

class _CheckingState extends State<_Checking> {
  @override
  void initState() {
    super.initState();
    widget.check(widget.path).then((r) {
      if (mounted) Navigator.pop(context, r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 14),
          Flexible(child: Text('Checking the folder…', style: t.body)),
        ],
      ),
    );
  }
}
