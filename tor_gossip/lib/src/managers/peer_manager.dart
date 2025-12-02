import 'dart:math';

class PeerManager {
  /// The set of known active peers (using Set to prevent duplicates).
  final Set<String> _knownPeers = {};

  /// A map to track failures. If a peer fails too often, we drop them.
  final Map<String, int> _failureCounts = {};

  /// Max failures before we purge a peer from the list.
  static const int _maxFailures = 3;

  /// Regex to validate Tor v3 addresses (56 chars + .onion).
  final RegExp _onionRegex = RegExp(r"^[a-z2-7]{56}\.onion$");

  PeerManager({List<String> bootstrapPeers = const []}) {
    for (var peer in bootstrapPeers) {
      addPeer(peer);
    }
  }

  /// Public helper to sanitize input and return a bare onion host (or null).
  /// Accepts:
  ///  - "abc...onion"
  ///  - "https://abc...onion/gossip"
  ///  - "http://abc...onion:1234/path"
  /// Returns: "abc...onion" or null if it cannot extract a valid host.
  String? sanitizeOnion(String input) {
    var s = input.trim().toLowerCase();

    // If it looks like a URL, try parsing it
    try {
      if (s.contains('://')) {
        final uri = Uri.parse(s);
        if (uri.host.isNotEmpty) {
          s = uri.host;
        } else {
          // fallback: strip scheme manually then split by '/'
          s = s.replaceFirst(RegExp(r'^.*://'), '');
          s = s.split('/').first;
        }
      } else {
        // may contain path or port; remove path portion
        s = s.split('/').first;
      }

      // remove port if present
      if (s.contains(':')) {
        s = s.split(':').first;
      }

      // final cleanup
      s = s.trim();

      if (_onionRegex.hasMatch(s)) {
        return s;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Adds a new peer if it is valid and unknown.
  /// Accepts full URL or bare host.
  bool addPeer(String onionAddress) {
    final cleanAddress = sanitizeOnion(onionAddress);
    if (cleanAddress == null) {
      print('⚠️ Ignored invalid onion address: $onionAddress');
      return false;
    }

    // 3. Add to set
    if (_knownPeers.contains(cleanAddress)) {
      return false; // Already known
    }

    _knownPeers.add(cleanAddress);
    print('➕ Added new peer: $cleanAddress');
    return true;
  }

  /// Removes a peer (e.g., if they are dead or malicious).
  void removePeer(String onionAddress) {
    final clean = sanitizeOnion(onionAddress) ?? onionAddress;
    _knownPeers.remove(clean);
    _failureCounts.remove(clean);
    print('🗑️ Removed peer: $clean');
  }

  /// Returns a random subset of peers to gossip with.
  /// [count] is usually 3-5 (the "Fanout" factor).
  /// [exclude] allows us to not send a message back to the person who sent it to us.
  List<String> getRandomPeers(int count, {Set<String>? exclude}) {
    // 1. Filter out excluded peers
    var candidates = _knownPeers.toList();
    if (exclude != null) {
      candidates = candidates.where((p) => !exclude.contains(p)).toList();
    }

    if (candidates.isEmpty) return [];

    // 2. Shuffle to randomize
    candidates.shuffle(Random());

    // 3. Take the requested amount (or fewer if we don't have enough)
    return candidates.take(count).toList();
  }

  /// Call this when a request to a peer fails.
  /// If they fail too many times, they are removed.
  void reportFailure(String onionAddress) {
    final clean = sanitizeOnion(onionAddress) ?? onionAddress;
    int currentFailures = (_failureCounts[clean] ?? 0) + 1;

    if (currentFailures >= _maxFailures) {
      print('💀 Peer $clean is dead. Removing.');
      removePeer(clean);
    } else {
      _failureCounts[clean] = currentFailures;
    }
  }

  /// Call this when a request succeeds to reset their failure count.
  void reportSuccess(String onionAddress) {
    final clean = sanitizeOnion(onionAddress) ?? onionAddress;
    if (_failureCounts.containsKey(clean)) {
      _failureCounts.remove(clean);
    }
  }

  /// Diagnostic: Get all peers
  List<String> getAllPeers() => _knownPeers.toList();
}