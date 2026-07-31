class GameException implements Exception {
  GameException(this.title, this.message);

  final String title;
  final String message;

  @override
  String toString() => '$title: $message';
}
