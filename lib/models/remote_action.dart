enum RemoteAction {
  up('Up'),
  down('Down'),
  left('Left'),
  right('Right'),
  select('Select'),
  back('Back'),
  home('Home'),
  volumeUp('Volume up'),
  volumeDown('Volume down'),
  mute('Mute'),
  power('Power'),
  play('Play'),
  rewind('Rewind'),
  forward('Forward'),
  input('Input');

  const RemoteAction(this.label);

  final String label;
}

class AppShortcut {
  const AppShortcut(this.label, this.id);

  final String label;
  final String id;
}
