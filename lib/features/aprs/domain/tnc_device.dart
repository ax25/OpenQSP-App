class TncDevice {
  const TncDevice({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is TncDevice && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
