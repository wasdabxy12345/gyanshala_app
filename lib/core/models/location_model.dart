class LocationItem {
  final String id;
  final String name;

  LocationItem({required this.id, required this.name});

  factory LocationItem.fromJson(Map<String, dynamic> json) {
    return LocationItem(
      id: json['id'].toString(),
      name: json['name'].toString(),
    );
  }
}
