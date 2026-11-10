import '../models/farly_device.dart';

/// Folds scan results into the saved list so each TV appears once.
///
/// A found device replaces the saved entry it matches by hardware identity or
/// address. With [matchByName], a saved entry whose old address went silent is
/// also matched by its own name, which covers a TV the router moved.
List<FarlyDevice> mergeDevices({
  required List<FarlyDevice> saved,
  required List<FarlyDevice> found,
  required DateTime seenAt,
  bool matchByName = true,
}) {
  final merged = collapseDevices(saved);
  final before = [...merged];
  final answered = {
    for (final device in found)
      if (device.host != null) device.host!,
  };
  for (final device in found) {
    final matches = merged.where((saved) {
      if (sameDevice(saved, device)) return true;
      return matchByName &&
          !answered.contains(saved.host) &&
          _sameName(saved, device);
    }).toList();
    if (matches.isEmpty && matchByName) {
      final rivals = found.where(
        (other) =>
            !identical(other, device) &&
            other.kind == device.kind &&
            !before.any((old) => sameDevice(old, other)),
      );
      final lone = rivals.isEmpty
          ? _loneSilentMatch(merged, device, answered)
          : null;
      // The match is a guess, so it keeps the entry but not the pairing:
      // worst case is pairing again, never controlling the wrong TV.
      if (lone != null) {
        matches.add(lone.copyWith(clearToken: true, clearClientKey: true));
        merged.remove(lone);
      }
    }
    var combined = device.copyWith(lastSeen: seenAt);
    for (final match in matches) {
      merged.remove(match);
      combined = _combine(match, combined, lastSeen: seenAt);
    }
    merged.add(combined);
  }
  merged.sort((a, b) {
    final aSeen = a.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bSeen = b.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = bSeen.compareTo(aSeen);
    if (byTime != 0) return byTime;
    return a.name.compareTo(b.name);
  });
  return merged;
}

/// Merges entries that already describe the same device, such as the Cast,
/// Android TV, and DIAL answers an earlier build saved separately.
List<FarlyDevice> collapseDevices(List<FarlyDevice> devices) {
  final collapsed = <FarlyDevice>[];
  for (final device in devices) {
    final index = collapsed.indexWhere((kept) => sameDevice(kept, device));
    if (index < 0) {
      collapsed.add(device);
      continue;
    }
    final kept = collapsed[index];
    final keptSeen = kept.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
    final seen = device.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
    collapsed[index] = seen.isAfter(keptSeen)
        ? _combine(kept, device, lastSeen: device.lastSeen)
        : _combine(device, kept, lastSeen: kept.lastSeen);
  }
  return collapsed;
}

/// Whether two entries are one device: the same announced identity, or the
/// same address at the same time.
bool sameDevice(FarlyDevice a, FarlyDevice b) {
  if (a.id == b.id) return true;
  if (a.uid != null && a.uid == b.uid) return true;
  return a.host != null && a.host == b.host;
}

/// Finds where [device] went after a merge changed its id or address.
FarlyDevice? findDevice(List<FarlyDevice> devices, FarlyDevice device) {
  for (final candidate in devices) {
    if (candidate.id == device.id) return candidate;
  }
  for (final candidate in devices) {
    if (sameDevice(candidate, device)) return candidate;
  }
  for (final candidate in devices) {
    if (_sameName(candidate, device)) return candidate;
  }
  return null;
}

bool _sameName(FarlyDevice a, FarlyDevice b) {
  if (a.hasGenericName || b.hasGenericName) return false;
  if (a.kind != b.kind) return false;
  if (a.uid != null && b.uid != null && a.uid != b.uid) return false;
  final unknown =
      a.brand == DeviceBrand.unknown || b.brand == DeviceBrand.unknown;
  if (!unknown && !_sameControl(a, b)) return false;
  return a.name.trim().toLowerCase() == b.name.trim().toLowerCase();
}

/// A saved TV that went silent and shares only a generic name (or none) with
/// [device] still matches it when nothing else could be that TV. Without a
/// stable name or uid, an address change is otherwise saved as a new copy.
FarlyDevice? _loneSilentMatch(
  List<FarlyDevice> saved,
  FarlyDevice device,
  Set<String> answered,
) {
  final silent = saved.where((s) {
    if (answered.contains(s.host) || s.kind != device.kind) return false;
    if (s.uid != null && device.uid != null && s.uid != device.uid) {
      return false;
    }
    if (!s.hasGenericName && !device.hasGenericName) return false;
    return s.brand == DeviceBrand.unknown ||
        device.brand == DeviceBrand.unknown ||
        _sameControl(s, device);
  }).toList();
  return silent.length == 1 ? silent.single : null;
}

/// [found] is the fresher answer. The better control path wins, and saved
/// pairing credentials carry over when the protocol is the same.
FarlyDevice _combine(
  FarlyDevice saved,
  FarlyDevice found, {
  required DateTime? lastSeen,
}) {
  final keepSaved = saved.brand.rank < found.brand.rank;
  final best = keepSaved ? saved : found;
  final host = found.host ?? saved.host;
  final credentials = _sameControl(saved, best) ? saved : null;
  final sameHost = saved.host == found.host;
  return FarlyDevice(
    id: keepSaved
        ? (sameHost || host == null
              ? saved.id
              : FarlyDevice.idFor(saved.brand, host))
        : found.id,
    name: saved.nameLocked ? saved.name : _preferredName(saved, found),
    kind: best.kind,
    brand: best.brand,
    host: host,
    port: keepSaved ? saved.port ?? found.port : found.port ?? saved.port,
    token: credentials?.token ?? found.token,
    clientKey: credentials?.clientKey ?? found.clientKey,
    descriptionUrl:
        found.descriptionUrl ?? (sameHost ? saved.descriptionUrl : null),
    uid: found.uid ?? saved.uid,
    source: found.source,
    lastSeen: lastSeen,
    icon: saved.icon ?? found.icon,
    nameLocked: saved.nameLocked || found.nameLocked,
  );
}

/// Cast and Android TV entries share the Android TV remote pairing.
bool _sameControl(FarlyDevice saved, FarlyDevice found) {
  if (saved.brand == found.brand) return true;
  const atv = {DeviceBrand.androidTv, DeviceBrand.chromecast};
  return atv.contains(saved.brand) && atv.contains(found.brand);
}

String _preferredName(FarlyDevice saved, FarlyDevice found) {
  if (!found.hasGenericName) return found.name;
  if (!saved.hasGenericName) return saved.name;
  return found.name;
}
