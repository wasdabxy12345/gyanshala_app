import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EntityManager extends StatefulWidget {
  final String tableName;
  final String entityName;
  final String? parentTable;
  final String? parentField;

  const EntityManager({
    super.key,
    required this.tableName,
    required this.entityName,
    this.parentTable,
    this.parentField,
  });

  @override
  State<EntityManager> createState() => _EntityManagerState();
}

class _EntityManagerState extends State<EntityManager> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _entities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final query = widget.parentTable != null
          ? _supabase
                .from(widget.tableName)
                .select('*, ${widget.parentTable}(name)')
          : _supabase.from(widget.tableName).select();

      final data = await query.order('name');
      if (mounted) {
        setState(() => _entities = List<Map<String, dynamic>>.from(data));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showForm([Map<String, dynamic>? entity]) async {
    final nameController = TextEditingController(text: entity?['name'] ?? '');
    String? selectedParentId = entity?[widget.parentField]?.toString();
    List<Map<String, dynamic>> parents = [];

    if (widget.parentTable != null) {
      final parentData = await _supabase
          .from(widget.parentTable!)
          .select()
          .order('name');
      parents = List<Map<String, dynamic>>.from(parentData);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // Added to handle dropdown state inside dialog
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            "${entity == null ? 'Add' : 'Edit'} ${widget.entityName}",
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.parentTable != null) ...[
                DropdownButtonFormField<String>(
                  initialValue: selectedParentId,
                  hint: Text(
                    "Select ${widget.entityName == 'Village' ? 'Cluster' : 'Village'}",
                  ),
                  items: parents
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id'].toString(),
                          child: Text(p['name'] ?? 'Unknown'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedParentId = val),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "${widget.entityName} Name",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final data = {'name': name};
                if (widget.parentField != null) {
                  data[widget.parentField!] = selectedParentId!;
                }

                try {
                  if (entity == null) {
                    await _supabase.from(widget.tableName).insert(data);
                  } else {
                    await _supabase
                        .from(widget.tableName)
                        .update(data)
                        .eq('id', entity['id']);
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  _fetchData();
                } catch (e) {
                  debugPrint("Error saving entity: $e");
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: _entities.isEmpty
          ? Center(child: Text("No ${widget.entityName}s found."))
          : ListView.separated(
              itemCount: _entities.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final item = _entities[i];
                final parentData = widget.parentTable != null
                    ? item[widget.parentTable]
                    : null;
                final parentName = parentData != null
                    ? parentData['name']
                    : null;

                return ListTile(
                  title: Text(
                    item['name'] ?? 'Unnamed',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: parentName != null ? Text("In $parentName") : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showForm(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await _showDeleteConfirm(
                            item['name'],
                          );
                          if (confirm == true) {
                            await _supabase
                                .from(widget.tableName)
                                .delete()
                                .eq('id', item['id']);
                            _fetchData();
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: Colors.deepOrange,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Future<bool?> _showDeleteConfirm(String? name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text(
          "Are you sure you want to delete '$name'? This may delete related items.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
