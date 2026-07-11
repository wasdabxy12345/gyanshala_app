import 'package:gyanshala_app/core/models/location_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _supabase = Supabase.instance.client;
Future<List<LocationItem>> fetchClusters() async {
  final List<dynamic> data = await _supabase.from('clusters').select().order('name');
  return data.map((e) => LocationItem.fromJson(e)).toList();
}

Future<List<LocationItem>> fetchVillages(String clusterId) async {
  final List<dynamic> data = await _supabase.from('villages').select().eq('cluster_id', clusterId).order('name');
  return data.map((e) => LocationItem.fromJson(e)).toList();
}

final bool isAuthenticated = _supabase.auth.currentUser != null;
final String columns = isAuthenticated ? '*' : 'id, name, village_id';

Future<List<LocationItem>> fetchSchools(String villageId) async {
  final List<dynamic> data = await _supabase.from('schools').select(columns).eq('village_id', villageId).order('name');
  return data.map((e) => LocationItem.fromJson(e)).toList();
}
