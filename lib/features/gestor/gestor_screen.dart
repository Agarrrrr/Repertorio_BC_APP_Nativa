import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:repertorio_bc/core/activity/activity_service.dart';
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
  Set<String> _onlineUserIds = {};
  int _analyticsDays = 30;
  RealtimeChannel? _presence;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
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
    return row?['nombre']?.toString() ?? 'Mi iglesia';
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
        analyticsDays: _analyticsDays,
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

  Future<void> _changeAnalyticsRange(int days) async {
    if (days == _analyticsDays || _sedeId == null) return;
    setState(() => _analyticsDays = days);
    await _run(() async {
      final metrics = await _repository.metricas(
        _sedeId!,
        cantos: _local,
        perfiles: _members,
        analyticsDays: days,
      );
      if (mounted) setState(() => _metrics = metrics);
    });
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
      if (mounted) {
        setState(() {
          _online = users.length;
          _onlineUserIds = users;
        });
      }
    });
    channel.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track({
          'user_id': SupabaseService.client.auth.currentUser?.id,
          'sede': sede,
          'plataforma': ActivityService.platform,
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
    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
      ),
      child: Scaffold(
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
                  _buildGlobal(),
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
      ),
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
          Text('Estado de la iglesia',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio:
                MediaQuery.sizeOf(context).width > 700 ? 1.7 : 1.25,
            children: [
              _MetricCard('Conectados ahora', _online, Icons.wifi_tethering,
                  Colors.green,
                  onTap: () => _showMetricDetail('online')),
              _MetricCard('Activos esta semana', metrics?.activosSemana ?? 0,
                  Icons.calendar_view_week, Colors.blue,
                  onTap: () => _showMetricDetail('active')),
              _MetricCard('Notificaciones reales', metrics?.notificaciones ?? 0,
                  Icons.notifications_active, Colors.amber.shade800,
                  onTap: () => _showMetricDetail('notifications')),
              _MetricCard('Offline preparado', metrics?.offline ?? 0,
                  Icons.offline_pin, Colors.teal,
                  onTap: () => _showMetricDetail('offline')),
              _MetricCard('Miembros', metrics?.miembros ?? 0, Icons.groups,
                  Colors.deepPurple,
                  onTap: () => _showMetricDetail('members')),
              _MetricCard('Partituras con voces', metrics?.conMidi ?? 0,
                  Icons.library_music, Colors.indigo,
                  detail: 'de ${metrics?.repertorio ?? 0} en la iglesia',
                  onTap: () => _showMetricDetail('midi')),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Partituras más consultadas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              DropdownButton<int>(
                value: _analyticsDays,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('1 mes')),
                  DropdownMenuItem(value: 180, child: Text('6 meses')),
                  DropdownMenuItem(value: 365, child: Text('1 año')),
                ],
                onChanged: (value) {
                  if (value != null) _changeAnalyticsRange(value);
                },
              ),
            ],
          ),
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
      emptyText: 'Esta iglesia todavía no tiene partituras.',
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
              value: 'edit',
              child: Text('Editar copia de la iglesia'),
            ),
            PopupMenuItem(
              value: 'remove',
              child: Text('Quitar de esta iglesia'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobal() {
    if (_globalLoading && _global.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final source = _global;
    final controller = _globalSearch;
    final query = controller.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? source
        : source
            .where((song) =>
                song.nombre.toLowerCase().contains(query) ||
                song.temas.any((topic) => topic.toLowerCase().contains(query)))
            .toList();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primaryContainer,
                Theme.of(context).colorScheme.surface,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Explora el catálogo',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Abre una opción para revisar la partitura y escuchar sus voces antes de añadirla a tu iglesia.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  hintText: 'Escribe el nombre de la partitura…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            controller.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                query.isEmpty
                    ? '${source.length} opciones para explorar'
                    : '${filtered.length} coincidencias',
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _CatalogEmpty(
                  hasQuery: query.isNotEmpty,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: filtered.length,
                  itemBuilder: (_, index) {
                    final song = filtered[index];
                    final hasMidi = song.midiArchivo?.isNotEmpty == true;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openCatalogDetail(
                          song,
                          canAdd: true,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                child: Icon(hasMidi
                                    ? Icons.library_music_rounded
                                    : Icons.picture_as_pdf_outlined),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.nombre,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      hasMidi
                                          ? 'PDF + ensamble de voces'
                                          : 'PDF disponible',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (song.temas.isNotEmpty)
                                      Text(
                                        song.temas.take(3).join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton.filledTonal(
                                tooltip: 'Añadir a la iglesia',
                                onPressed: () => _addGlobal(song),
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
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
              text: 'No hay carpetas o eventos para esta iglesia.',
            ),
          ..._events.map((event) {
            final scoreCount = (event['eventos_cantos'] as List?)?.length ?? 0;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.folder_copy_outlined),
                title: Text(event['nombre']?.toString() ?? 'Sin nombre'),
                subtitle: Text(
                  '${_formatDateOnly(event['fecha'])} · $scoreCount partituras',
                ),
                onTap: () => _editEventSongs(event),
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
        itemCount: _members.isEmpty ? 2 : _members.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.calendar_view_week, size: 18),
                    label: Text(
                        '${_metrics?.activosSemana ?? 0} activos esta semana'),
                    onPressed: () => _showMetricDetail('active'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.notifications_active, size: 18),
                    label: Text(
                        '${_metrics?.notificaciones ?? 0} con notificaciones'),
                    onPressed: () => _showMetricDetail('notifications'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.wifi_tethering, size: 18),
                    label: Text('$_online conectados ahora'),
                    onPressed: () => _showMetricDetail('online'),
                  ),
                ],
              ),
            );
          }
          if (_members.isEmpty) {
            return const _EmptyState(
              icon: Icons.group_off_outlined,
              text: 'No hay miembros registrados en esta iglesia.',
            );
          }
          final member = _members[index - 1];
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
                '${member['rol']} · ${member['estado']}'
                '${member['_app_platform'] == null ? '' : ' · ${_platformLabel(member['_app_platform'])}'}'
                '${hasPush ? ' · notificaciones' : ''}',
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

  Future<void> _openCatalogDetail(
    Canto song, {
    required bool canAdd,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogDetailScreen(
          canto: song,
          onAdd: canAdd ? () => _addGlobal(song) : null,
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

  Future<void> _editSong(Canto song) async {
    final iglesia = _sedeId;
    if (iglesia == null) return;
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
          sedeId: iglesia,
          type: 'pdf',
          bytes: result.pdf!,
        );
      }
      if (result.midi != null) {
        midi = await _repository.upload(
          sedeId: iglesia,
          type: 'midi',
          bytes: result.midi!,
        );
      }
      await _repository.guardarLocal(
        original: song,
        sedeId: iglesia,
        nombre: result.name,
        temas: result.topics,
        archivo: pdf,
        midi: midi,
        quitarMidi: result.removeMidi,
      );
      _showMessage('Partitura de la iglesia actualizada.');
      await _reload();
    });
  }

  Future<void> _confirmRemove(Canto song) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar de esta iglesia'),
        content: Text(
          '${song.nombre} dejará de estar disponible en $_sedeName. '
          'El catálogo global y las demás iglesias no cambiarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar'),
          ),
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

  String _formatTimestamp(Object? value) {
    final date = value == null ? null : DateTime.tryParse(value.toString());
    if (date == null) return 'Sin acceso registrado desde la app';
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final difference = today.difference(day).inDays;
    final hour =
        local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final time = '$hour:$minute ${local.hour >= 12 ? 'p. m.' : 'a. m.'}';
    if (difference == 0) return 'Hoy, $time';
    if (difference == 1) return 'Ayer, $time';
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic'
    ];
    final year = local.year == now.year ? '' : ' ${local.year}';
    return '${local.day} ${months[local.month - 1]}$year, $time';
  }

  String _formatDateOnly(Object? value) {
    final date = value == null ? null : DateTime.tryParse(value.toString());
    if (date == null) return 'Sin fecha';
    final local = date.toLocal();
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre'
    ];
    return '${local.day} de ${months[local.month - 1]} de ${local.year}';
  }

  String _platformLabel(Object? value) => switch (value?.toString()) {
        'ios' => 'iOS',
        'android' => 'Android',
        'web' => 'Web',
        _ => 'Sin plataforma',
      };

  Future<void> _showMetricDetail(String type) async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    late final String title;
    late final List<Map<String, dynamic>> members;
    if (type == 'notifications') {
      title = 'Notificaciones activas';
      members = _members.where((row) => row['_push_active'] == true).toList();
    } else if (type == 'active') {
      title = 'Activos esta semana';
      members = _members.where((row) {
        final date =
            DateTime.tryParse(row['_app_last_access']?.toString() ?? '');
        return date != null && date.toUtc().isAfter(cutoff);
      }).toList();
    } else if (type == 'online') {
      title = 'Conectados en este momento';
      members = _members
          .where((row) => _onlineUserIds.contains(row['id'].toString()))
          .toList();
    } else if (type == 'offline') {
      title = 'Descarga offline preparada';
      members = _members.where((row) => row['offline_ready'] == true).toList();
    } else if (type == 'members') {
      title = 'Miembros de la iglesia';
      members = List<Map<String, dynamic>>.from(_members);
    } else {
      title = 'Partituras con voces de ensayo';
      members = const [];
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 620,
          height: MediaQuery.sizeOf(context).height * .62,
          child: type == 'midi'
              ? (_local
                      .where((song) => song.midiArchivo?.isNotEmpty == true)
                      .isEmpty
                  ? const Text(
                      'No hay partituras con voces MIDI en esta iglesia.')
                  : ListView(
                      shrinkWrap: true,
                      children: _local
                          .where((song) => song.midiArchivo?.isNotEmpty == true)
                          .map((song) => ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.graphic_eq_rounded),
                                ),
                                title: Text(song.nombre),
                                subtitle: Text(song.temas.isEmpty
                                    ? 'Ensamble disponible'
                                    : song.temas.join(' · ')),
                                onTap: () {
                                  Navigator.pop(dialogContext);
                                  _openCatalogDetail(song, canAdd: false);
                                },
                              ))
                          .toList(),
                    ))
              : (members.isEmpty
                  ? const Text('No hay registros para mostrar.')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: members.length,
                      itemBuilder: (_, index) {
                        final member = members[index];
                        final notificationRegistered =
                            member['_push_registered_at'];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (member['nombre']?.toString() ?? '?')
                                  .characters
                                  .first
                                  .toUpperCase(),
                            ),
                          ),
                          title: Text(
                              member['nombre']?.toString() ?? 'Sin nombre'),
                          subtitle: Text(
                            type == 'notifications'
                                ? 'Registrado: ${_formatTimestamp(notificationRegistered)}\n'
                                    'Último acceso en app: ${_formatTimestamp(member['_app_last_access'])} · ${_platformLabel(member['_app_platform'])}'
                                : '${member['rol']} · ${member['estado']}\n'
                                    'Último acceso en app: ${_formatTimestamp(member['_app_last_access'])} · ${_platformLabel(member['_app_platform'])}',
                          ),
                          isThreeLine: true,
                        );
                      },
                    )),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editEventSongs(Map<String, dynamic> event) async {
    final selected = ((event['eventos_cantos'] as List?) ?? const [])
        .map((row) => (row as Map)['canto_id'].toString())
        .toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(event['nombre']?.toString() ?? 'Carpeta'),
          content: SizedBox(
            width: 560,
            child: _local.isEmpty
                ? const Text('La iglesia todavía no tiene partituras.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _local.length,
                    itemBuilder: (_, index) {
                      final song = _local[index];
                      return CheckboxListTile(
                        value: selected.contains(song.id),
                        title: Text(song.nombre),
                        onChanged: (checked) => setDialogState(() {
                          if (checked == true) {
                            selected.add(song.id);
                          } else {
                            selected.remove(song.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Guardar selección'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _run(() async {
      await _repository.guardarCantosEvento(
        event['id'].toString(),
        result.toList(),
      );
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
      tooltip: 'Cambiar iglesia administrada',
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
      {this.detail, this.onTap});
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                detail ?? label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
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
                    padding: const EdgeInsets.only(bottom: 24),
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

class _CatalogEmpty extends StatelessWidget {
  const _CatalogEmpty({
    required this.hasQuery,
  });

  final bool hasQuery;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasQuery ? Icons.search_off_rounded : Icons.music_off_outlined,
                size: 54,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                hasQuery
                    ? 'No encontramos esa partitura'
                    : 'El catálogo está vacío',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (hasQuery) ...[
                const SizedBox(height: 6),
                const Text(
                  'Prueba con una parte del título o con otro tema.',
                  textAlign: TextAlign.center,
                ),
              ],
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
  const _SongEditor({required this.song});

  final Canto song;

  @override
  State<_SongEditor> createState() => _SongEditorState();
}

class _SongEditorState extends State<_SongEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.song.nombre);
  late final TextEditingController _topics =
      TextEditingController(text: widget.song.temas.join(', '));
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
    final existingMidi = widget.song.midiArchivo?.isNotEmpty == true;
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
              'Editar partitura de la iglesia',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 150,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
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
              label: _pdfName ?? 'Reemplazar PDF',
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
                  if (_name.text.trim().isEmpty) return;
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
                label: const Text('Guardar en esta iglesia'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileButton extends StatelessWidget {
  const _FileButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
