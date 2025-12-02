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

  /// Adds a new peer if it is valid and unknown.
  bool addPeer(String onionAddress) {
    // 1. Clean the string
    final cleanAddress = onionAddress.trim().toLowerCase();

    // 2. Validate format (Basic security check)
    if (!_onionRegex.hasMatch(cleanAddress)) {
      print('⚠️ Ignored invalid onion address: $cleanAddress');
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
    _knownPeers.remove(onionAddress);
    _failureCounts.remove(onionAddress);
    print('🗑️ Removed peer: $onionAddress');
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
    int currentFailures = (_failureCounts[onionAddress] ?? 0) + 1;

    if (currentFailures >= _maxFailures) {
      print('💀 Peer $onionAddress is dead. Removing.');
      removePeer(onionAddress);
    } else {
      _failureCounts[onionAddress] = currentFailures;
    }
  }

  /// Call this when a request succeeds to reset their failure count.
  void reportSuccess(String onionAddress) {
    if (_failureCounts.containsKey(onionAddress)) {
      _failureCounts.remove(onionAddress);
    }
  }

  /// Diagnostic: Get all peers
  List<String> getAllPeers() => _knownPeers.toList();
}