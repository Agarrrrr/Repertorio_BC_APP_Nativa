import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/features/gestor/gestor_preview.dart';
import 'package:repertorio_bc/features/gestor/gestor_repository.dart';
import 'package:repertorio_bc/models/canto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GestorScreen extends ConsumerStatefulWidget {
  const GestorScreen({super.key});

  @override
  ConsumerState<GestorScreen> createState() => _GestorScreenState();
}

class _GestorScreenState extends ConsumerState<GestorScreen>
    with SingleTickerProviderStateMixin {
  final GestorRepository _repository = GestorRepository();
  final TextEditingController _reminder = TextEditingController();
  final TextEditingController _localSearch = TextEditingController();
  final TextEditingController _globalSearch = TextEditingController();
  late final TabController _tabs;

  List<Map<String, dynamic>> _sedes = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _events = [];
  List<Canto> _local = [];
  List<Canto> _global = [];
  GestorMetrics? _metrics;
  String? _sedeId;
  bool _loading = true;
  bool _globalLoading = true;
  bool _working = false;
  int _online = 0;
  RealtimeChannel? _presence;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _reminder.dispose();
    _localSearch.dispose();
    _globalSearch.dispose();
    _tabs.dispose();
    final channel = _presence;
    if (channel != null) SupabaseService.client.removeChannel(channel);
    super.dispose();
  }

  bool get _canChangeSede {
    final role = ref.read(perfilProvider).value?.rol;
    return role == 'director_estatal' || role == 'superadmin';
  }

  String get _sedeName {
    final row = _sedes.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id']?.toString() == _sedeId,
          orElse: () => null,
        );
    return row?['nombre']?.toString() ?? 'Mi sede';
  }

  Future<void> _bootstrap() async {
    final profile = ref.read(perfilProvider).value;
    if (profile == null) return;
    try {
      final sedes = await _repository.sedes();
      if (!mounted) return;
      _sedes = sedes;
      _sedeId = profile.coroId.isNotEmpty
          ? profile.coroId
          : (sedes.isNotEmpty ? sedes.first['id'].toString() : null);
      await _reload();
    } catch (error) {
      _showError(error);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    final sede = _sedeId;
    if (sede == null) return;
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _repository.repertorio(sede),
        _repository.miembros(sede),
        _repository.eventos(sede),
      ]);
      final local = values[0] as List<Canto>;
      final members = values[1] as List<Map<String, dynamic>>;
      final metrics = await _repository.metricas(
        sede,
        cantos: local,
        perfiles: members,
      );
      if (!mounted) return;
      setState(() {
        _local = local;
        _members = members;
        _events = values[2] as List<Map<String, dynamic>>;
        _metrics = metrics;
        _loading = false;
      });
      await _connectPresence(sede);
      unawaited(_loadGlobal());
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _loadGlobal() async {
    if (mounted) setState(() => _globalLoading = true);
    try {
      final global = await _repository.catalogoGlobal();
      if (mounted) setState(() => _global = global);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _globalLoading = false);
    }
  }

  Future<void> _connectPresence(String sede) async {
    final previous = _presence;
    if (previous != null) await SupabaseService.client.removeChannel(previous);
    final channel = SupabaseService.client.channel('main-$sede');
    channel.onPresenceSync((_) {
      final state = channel.presenceState();
      final users = <String>{};
      for (final presence in state) {
        final payload = presence.presences;
        for (final entry in payload) {
          final id = entry.payload['user_id']?.toString();
          users.add(id ?? entry.presenceRef);
        }
      }
      if (mounted) setState(() => _online = users.length);
    });
    channel.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track({
          'user_id': SupabaseService.client.auth.currentUser?.id,
          'sede': sede,
          'online_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
    _presence = channel;
  }

  Future<void> _selectSede(String value) async {
    if (!_canChangeSede || value == _sedeId) return;
    setState(() => _sedeId = value);
    await _reload();
  }

  Future<void> _sendReminder() async {
    final sede = _sedeId;
    if (sede == null || _reminder.text.trim().isEmpty) return;
    await _run(() async {
      await _repository.enviarRecordatorio(sede, _reminder.text);
      _reminder.clear();
      _showMessage('Recordatorio enviado a $_sedeName.');
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final text = error.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.red.shade800),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.green.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver al repertorio',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        titleSpacing: 0,
        title: _SedeSelector(
          title: _sedeName,
          canChange: _canChangeSede,
          selected: _sedeId,
          sedes: _sedes,
          onSelected: _selectSede,
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.space_dashboard_outlined), text: 'Resumen'),
            Tab(icon: Icon(Icons.library_music_outlined), text: 'Partituras'),
            Tab(icon: Icon(Icons.public_rounded), text: 'Catálogo'),
            Tab(icon: Icon(Icons.graphic_eq_rounded), text: 'Ensamble'),
            Tab(icon: Icon(Icons.folder_copy_outlined), text: 'Carpetas'),
            Tab(icon: Icon(Icons.groups_outlined), text: 'Miembros'),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            TabBarView(
              controller: _tabs,
              children: [
                _buildOverview(),
                _buildLocal(),
                _buildGlobal(ensembleOnly: false),
                _buildGlobal(ensembleOnly: true),
                _buildEvents(),
                _buildMembers(),
              ],
            ),
          if (_working)
            ColoredBox(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      floatingActionButton: !_loading && _tabs.index == 1
          ? FloatingActionButton.extended(
              onPressed: () => _editSong(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva partitura'),
            )
          : null,
    );
  }

  Widget _buildOverview() {
    final metrics = _metrics;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Comunicación', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Añadir recordatorio',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text('Se enviará únicamente a $_sedeName.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reminder,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Escribe aquí el aviso para el coro…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sendReminder,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Enviar recordatorio'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Estado de la sede',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              _MetricCard('Conectados ahora', _online, Icons.wifi_tethering,
                  Colors.green),
              _MetricCard('Activos esta semana', metrics?.activosSemana ?? 0,
                  Icons.calendar_view_week, Colors.blue),
              _MetricCard('Notificaciones reales', metrics?.notificaciones ?? 0,
                  Icons.notifications_active, Colors.amber.shade800),
              _MetricCard('Offline preparado', metrics?.offline ?? 0,
                  Icons.offline_pin, Colors.teal),
              _MetricCard('Miembros', metrics?.miembros ?? 0, Icons.groups,
                  Colors.deepPurple),
              _MetricCard('Partituras / MIDI', metrics?.repertorio ?? 0,
                  Icons.library_music, Colors.indigo,
                  detail: '${metrics?.conMidi ?? 0} con MIDI'),
            ],
          ),
          const SizedBox(height: 20),
          Text('Distribución de voces',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (metrics?.voces.entries ?? const Iterable.empty())
                .map((entry) => Chip(
                      avatar: const Icon(Icons.record_voice_over, size: 17),
                      label: Text('${entry.key}: ${entry.value}'),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          Text('Partituras más consultadas · 30 días',
              style: Theme.of(context).textTheme.titleMedium),
          if (metrics?.topCantos.isEmpty ?? true)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Todavía no hay uso suficiente para mostrar.'),
            )
          else
            ...metrics!.topCantos.map((row) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bar_chart_rounded),
                  title: Text(row['nombre']?.toString() ?? 'Sin nombre'),
                  trailing: Text('${row['vistas']} vistas'),
                )),
          const SizedBox(height: 12),
          Text('Actividad reciente',
              style: Theme.of(context).textTheme.titleMedium),
          if (metrics?.auditoria.isEmpty ?? true)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Sin movimientos recientes.'),
            )
          else
            ...metrics!.auditoria.map((row) {
              final details = row['detalles'] as Map?;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded),
                title: Text(
                  details?['canto_nombre']?.toString() ??
                      details?['mensaje']?.toString() ??
                      row['accion']?.toString() ??
                      'Movimiento',
                ),
                subtitle: Text(row['accion']?.toString() ?? ''),
              );
            }),
          if (metrics?.errores.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Text('Alertas técnicas recientes',
                style: Theme.of(context).textTheme.titleMedium),
            ...metrics!.errores.map((row) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade800),
                  title: Text(row['mensaje']?.toString() ?? 'Error'),
                  subtitle: Text(row['fecha']?.toString() ?? ''),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildLocal() {
    return _SearchableSongList(
      controller: _localSearch,
      songs: _local,
      emptyText: 'Esta sede todavía no tiene partituras.',
      onChanged: () => setState(() {}),
      itemBuilder: (song) => ListTile(
        leading: CircleAvatar(
          child: Icon(song.midiArchivo?.isNotEmpty == true
              ? Icons.queue_music
              : Icons.picture_as_pdf),
        ),
        title: Text(song.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle:
            Text(song.temas.isEmpty ? 'Sin temas' : song.temas.join(' · ')),
        onTap: () => _openPdf(song),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'preview') _openPdf(song);
            if (value == 'edit') _editSong(song);
            if (value == 'remove') _confirmRemove(song);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'preview', child: Text('Vista previa')),
            PopupMenuItem(
                value: 'edit', child: Text('Editar copia de la sede')),
            PopupMenuItem(value: 'remove', child: Text('Quitar de esta sede')),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobal({required bool ensembleOnly}) {
    if (_globalLoading && _global.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final source = ensembleOnly
        ? _global.where((song) => song.midiArchivo?.isNotEmpty == true).toList()
        : _global;
    return _SearchableSongList(
      controller: _globalSearch,
      songs: source,
      emptyText: ensembleOnly
          ? 'No hay MIDI disponibles para escuchar.'
          : 'No hay partituras en el catálogo global.',
      onChanged: () => setState(() {}),
      itemBuilder: (song) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          leading: Icon(ensembleOnly ? Icons.graphic_eq : Icons.public),
          title: Text(song.nombre),
          subtitle: Text(ensembleOnly
              ? 'Reproductor de ensamble'
              : '${song.temas.join(' · ')}${song.midiArchivo != null ? ' · MIDI' : ''}'),
          onTap: () => ensembleOnly ? _openEnsemble(song) : _openPdf(song),
          trailing: ensembleOnly
              ? const Icon(Icons.play_circle_outline_rounded)
              : Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      tooltip: 'Vista previa',
                      onPressed: () => _openPdf(song),
                      icon: const Icon(Icons.visibility_outlined),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Agregar a la sede',
                      onPressed: () => _addGlobal(song),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEvents() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          FilledButton.icon(
            onPressed: _createEvent,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Nueva carpeta o evento'),
          ),
          const SizedBox(height: 12),
          if (_events.isEmpty)
            const _EmptyState(
              icon: Icons.folder_off_outlined,
              text: 'No hay carpetas o eventos para esta sede.',
            ),
          ..._events.map((event) {
            final scoreCount = (event['eventos_cantos'] as List?)?.length ?? 0;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.folder_copy_outlined),
                title: Text(event['nombre']?.toString() ?? 'Sin nombre'),
                subtitle:
                    Text('${event['fecha'] ?? ''} · $scoreCount partituras'),
                trailing: IconButton(
                  tooltip: 'Eliminar carpeta',
                  onPressed: () => _confirmDeleteEvent(event),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMembers() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _members.isEmpty ? 1 : _members.length,
        itemBuilder: (context, index) {
          if (_members.isEmpty) {
            return const _EmptyState(
              icon: Icons.group_off_outlined,
              text: 'No hay miembros registrados en esta sede.',
            );
          }
          final member = _members[index];
          final active = member['estado'] == 'activo';
          final hasPush = member['_push_active'] == true;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                    (member['nombre']?.toString() ?? '?')[0].toUpperCase()),
              ),
              title: Text(member['nombre']?.toString() ?? 'Sin nombre'),
              subtitle: Text(
                '${member['rol']} · ${member['estado']}${hasPush ? ' · notificaciones' : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _changeMember(member, value),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: active ? 'suspendido' : 'activo',
                    child: Text(active ? 'Suspender' : 'Activar'),
                  ),
                  const PopupMenuItem(
                      value: 'rol:miembro', child: Text('Rol: miembro')),
                  const PopupMenuItem(
                      value: 'rol:delegado', child: Text('Rol: delegado')),
                  const PopupMenuItem(
                      value: 'rol:subdirector',
                      child: Text('Rol: subdirector')),
                  const PopupMenuItem(
                      value: 'rol:director', child: Text('Rol: director')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPdf(Canto song) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GestorPdfPreview(canto: song)),
    );
  }

  Future<void> _openEnsemble(Canto song) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Reproductor de ensamble')),
          body: SafeArea(child: EnsemblePlayer(canto: song)),
        ),
      ),
    );
  }

  Future<void> _addGlobal(Canto song) async {
    final sede = _sedeId;
    if (sede == null) return;
    await _run(() async {
      await _repository.agregarGlobal(song, sede);
      _showMessage('${song.nombre} se agregó como copia independiente.');
      await _reload();
    });
  }

  Future<void> _editSong([Canto? song]) async {
    final sede = _sedeId;
    if (sede == null) return;
    final result = await showModalBottomSheet<_SongDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SongEditor(song: song),
    );
    if (result == null) return;
    await _run(() async {
      String? pdf;
      String? midi;
      if (result.pdf != null) {
        pdf = await _repository.upload(
          sedeId: sede,
          type: 'pdf',
          bytes: result.pdf!,
        );
      }
      if (result.midi != null) {
        midi = await _repository.upload(
          sedeId: sede,
          type: 'midi',
          bytes: result.midi!,
        );
      }
      await _repository.guardarLocal(
        original: song,
        sedeId: sede,
        nombre: result.name,
        temas: result.topics,
        archivo: pdf,
        midi: midi,
        quitarMidi: result.removeMidi,
      );
      _showMessage(
          song == null ? 'Partitura creada.' : 'Copia de la sede actualizada.');
      await _reload();
    });
  }

  Future<void> _confirmRemove(Canto song) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar de esta sede'),
        content: Text(
          '${song.nombre} dejará de estar disponible en $_sedeName. '
          'El catálogo global y las demás sedes no cambiarán.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quitar')),
        ],
      ),
    );
    if (yes != true || _sedeId == null) return;
    await _run(() async {
      await _repository.quitarDeSede(song, _sedeId!);
      await _reload();
    });
  }

  Future<void> _createEvent() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva carpeta o evento'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Crear')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || _sedeId == null) return;
    await _run(() async {
      await _repository.crearEvento(_sedeId!, result, DateTime.now());
      await _reload();
    });
  }

  Future<void> _confirmDeleteEvent(Map<String, dynamic> event) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar carpeta'),
        content: Text(
            '¿Eliminar “${event['nombre']}”? Las partituras no se eliminarán.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() async {
      await _repository.eliminarEvento(event['id'].toString());
      await _reload();
    });
  }

  Future<void> _changeMember(Map<String, dynamic> member, String value) async {
    await _run(() async {
      if (value.startsWith('rol:')) {
        await _repository.actualizarMiembro(
          member['id'].toString(),
          rol: value.substring(4),
        );
      } else {
        await _repository.actualizarMiembro(member['id'].toString(),
            estado: value);
      }
      await _reload();
    });
  }
}

class _SedeSelector extends StatelessWidget {
  const _SedeSelector({
    required this.title,
    required this.canChange,
    required this.selected,
    required this.sedes,
    required this.onSelected,
  });

  final String title;
  final bool canChange;
  final String? selected;
  final List<Map<String, dynamic>> sedes;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (!canChange) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Administración', style: TextStyle(fontSize: 11)),
          Text(title, overflow: TextOverflow.ellipsis),
        ],
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Cambiar sede administrada',
      initialValue: selected,
      onSelected: onSelected,
      itemBuilder: (_) => sedes
          .map((sede) => PopupMenuItem(
                value: sede['id'].toString(),
                child: Text('${sede['municipio'] ?? 'BC'} · ${sede['nombre']}'),
              ))
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.expand_more_rounded),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon, this.color,
      {this.detail});
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Text('$value',
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
            Text(detail ?? label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _SearchableSongList extends StatelessWidget {
  const _SearchableSongList({
    required this.controller,
    required this.songs,
    required this.emptyText,
    required this.onChanged,
    required this.itemBuilder,
  });
  final TextEditingController controller;
  final List<Canto> songs;
  final String emptyText;
  final VoidCallback onChanged;
  final Widget Function(Canto) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final query = controller.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? songs
        : songs
            .where((song) =>
                song.nombre.toLowerCase().contains(query) ||
                song.temas.any((topic) => topic.toLowerCase().contains(query)))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o tema…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixText: '${filtered.length}',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyState(icon: Icons.search_off_rounded, text: emptyText)
              : RefreshIndicator(
                  onRefresh: () async => onChanged(),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filtered.length,
                    itemBuilder: (_, index) => itemBuilder(filtered[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _SongDraft {
  const _SongDraft({
    required this.name,
    required this.topics,
    this.pdf,
    this.midi,
    this.removeMidi = false,
  });
  final String name;
  final List<String> topics;
  final Uint8List? pdf;
  final Uint8List? midi;
  final bool removeMidi;
}

class _SongEditor extends StatefulWidget {
  const _SongEditor({this.song});
  final Canto? song;

  @override
  State<_SongEditor> createState() => _SongEditorState();
}

class _SongEditorState extends State<_SongEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.song?.nombre ?? '');
  late final TextEditingController _topics =
      TextEditingController(text: widget.song?.temas.join(', ') ?? '');
  Uint8List? _pdf;
  Uint8List? _midi;
  String? _pdfName;
  String? _midiName;
  bool _removeMidi = false;

  @override
  void dispose() {
    _name.dispose();
    _topics.dispose();
    super.dispose();
  }

  Future<void> _pick(bool pdf) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: pdf ? const ['pdf'] : const ['mid', 'midi'],
      withData: true,
      allowMultiple: false,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() {
      if (pdf) {
        _pdf = file!.bytes;
        _pdfName = file.name;
      } else {
        _midi = file!.bytes;
        _midiName = file.name;
        _removeMidi = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final existingMidi = widget.song?.midiArchivo?.isNotEmpty == true;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.song == null
                  ? 'Nueva partitura'
                  : 'Editar copia de la sede',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 150,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _topics,
              decoration: const InputDecoration(
                labelText: 'Temas separados por coma',
                hintText: 'Santa Cena, Avivamiento, Jóvenes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _FileButton(
              icon: Icons.picture_as_pdf_outlined,
              label: _pdfName ??
                  (widget.song == null
                      ? 'Seleccionar PDF (obligatorio)'
                      : 'Reemplazar PDF'),
              onTap: () => _pick(true),
            ),
            const SizedBox(height: 8),
            _FileButton(
              icon: Icons.queue_music_outlined,
              label: _midiName ?? 'Seleccionar o reemplazar MIDI',
              onTap: () => _pick(false),
            ),
            if (existingMidi || _midi != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quitar MIDI de esta partitura'),
                value: _removeMidi,
                onChanged: (value) => setState(() {
                  _removeMidi = value ?? false;
                  if (_removeMidi) {
                    _midi = null;
                    _midiName = null;
                  }
                }),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  if (_name.text.trim().isEmpty ||
                      (widget.song == null && _pdf == null)) {
                    return;
                  }
                  Navigator.pop(
                    context,
                    _SongDraft(
                      name: _name.text.trim(),
                      topics: _topics.text
                          .split(',')
                          .map((value) => value.trim())
                          .where((value) => value.isNotEmpty)
                          .toSet()
                          .toList(),
                      pdf: _pdf,
                      midi: _midi,
                      removeMidi: _removeMidi,
                    ),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar en esta sede'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileButton extends StatelessWidget {
  const _FileButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          alignment: Alignment.centerLeft,
        ),
      );
}
