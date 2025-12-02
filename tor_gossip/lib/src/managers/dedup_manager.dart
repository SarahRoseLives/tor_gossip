import 'dart:collection';

class DedupManager {
  /// How many message IDs to keep in memory.
  /// 2000 IDs is roughly ~75KB of RAM (negligible).
  final int _maxHistory;

  /// We use a Queue to efficiently remove the oldest items.
  final Queue<String> _idQueue = Queue();

  /// We use a Set for O(1) instant lookup speed.
  final Set<String> _idSet = {};

  DedupManager({int maxHistory = 2000}) : _maxHistory = maxHistory;

  /// Checks if we have seen this message ID before.
  bool isDuplicate(String messageId) {
    return _idSet.contains(messageId);
  }

  /// Marks a message ID as seen.
  void markSeen(String messageId) {
    if (_idSet.contains(messageId)) return;

    _idSet.add(messageId);
    _idQueue.add(messageId);

    // If we exceed history size, remove the oldest ID (FIFO)
    if (_idQueue.length > _maxHistory) {
      final oldId = _idQueue.removeFirst();
      _idSet.remove(oldId);
    }
  }

  /// Clears history (useful for testing or resetting).
  void clear() {
    _idQueue.clear();
    _idSet.clear();
  }
}