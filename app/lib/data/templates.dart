/// Starting text for new notes. A note at `Templates/<Type>.md` (for example
/// Templates/Meeting.md) replaces the built-in one, so templates can be
/// edited in Comb or in Obsidian like any note.
library;

import 'models.dart';

const builtInTemplates = <NoteKind, String>{
  NoteKind.meeting: '## Attendees\n\n\n## Agenda\n\n\n## Notes\n\n\n## Actions\n- [ ] \n',
  NoteKind.call: '**With:** \n**Languages:** \n\n## Summary\n\n\n## Notes\n\n\n## Actions\n- [ ] \n',
  NoteKind.project: '## Goal\n\n\n## Status\n\n\n## Notes\n',
  NoteKind.person: '## About\n\n\n## Notes\n',
  NoteKind.daily: '## Today\n- [ ] \n\n## Notes\n',
};

String templatePath(NoteKind kind) => 'Templates/${kind.label}.md';
