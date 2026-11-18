import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../data/remote/panel_api.dart';
import '../../../domain/entities/panel.dart';
import '../../../domain/entities/user.dart';
import '../../panel/presentation/panel_widgets.dart';

/// Administración de usuarios y roles (RF-03, RF-04). Solo administrador.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  static const _limit = 20;

  late final PanelApi _api = context.read<PanelApi>();
  final _search = TextEditingController();
  Timer? _debounce;
  UserRole? _role;
  int _offset = 0;
  late Future<Paged<ManagedUser>> _page = _load();

  Future<Paged<ManagedUser>> _load() => _api.users(
    search: _search.text.trim(),
    role: _role,
    limit: _limit,
    offset: _offset,
  );

  void _reload({bool resetPage = false}) {
    if (resetPage) _offset = 0;
    setState(() {
      _page = _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _openForm({ManagedUser? user}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Provider.value(
        value: _api,
        child: _UserFormDialog(user: user),
      ),
    );
    if (saved == true && mounted) {
      showPanelMessage(
        context,
        user == null ? 'Usuario creado.' : 'Usuario actualizado.',
      );
      _reload();
    }
  }

  Future<void> _toggleActive(ManagedUser u) async {
    final deactivate = u.active;
    if (deactivate) {
      final ok = await confirmAction(
        context,
        title: 'Desactivar usuario',
        message:
            '${u.fullName} no podrá iniciar sesión y sus sesiones abiertas se cerrarán. '
            'Sus registros se conservan.',
        confirmLabel: 'Desactivar',
        destructive: true,
      );
      if (!ok) return;
    }
    try {
      await _api.updateUser(u.id, active: !u.active);
      if (!mounted) return;
      showPanelMessage(
        context,
        deactivate ? 'Usuario desactivado.' : 'Usuario activado.',
      );
      _reload();
    } catch (e) {
      if (mounted) showPanelMessage(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = panelUser(context);
    return PanelPage(
      title: 'Usuarios',
      subtitle: 'Cuentas del sistema y sus roles.',
      actions: [
        FilledButton.icon(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Nuevo usuario'),
        ),
      ],
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Buscar por nombre o correo...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 350),
                          () => _reload(resetPage: true),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<UserRole?>(
                      isExpanded: true,
                      initialValue: _role,
                      decoration: const InputDecoration(
                        labelText: 'Rol',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos'),
                        ),
                        for (final r in UserRole.values)
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                      onChanged: (r) {
                        _role = r;
                        _reload(resetPage: true);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<Paged<ManagedUser>>(
                future: _page,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ErrorBox(
                      message: errorMessage(snap.error!),
                      onRetry: _reload,
                    );
                  }
                  if (!snap.hasData) return const LoadingBox();
                  final page = snap.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelTable(
                        columns: const [
                          'Nombre',
                          'Correo',
                          'Rol',
                          'Estado',
                          'Último acceso',
                          'Acciones',
                        ],
                        emptyMessage: 'No se encontraron usuarios.',
                        rows: [
                          for (final u in page.items)
                            _row(u, isMe: u.id == me.id),
                        ],
                      ),
                      Pager(
                        offset: _offset,
                        limit: _limit,
                        total: page.total,
                        onChanged: (o) {
                          _offset = o;
                          _reload();
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _row(ManagedUser u, {required bool isMe}) {
    return DataRow(
      cells: [
        DataCell(
          Text(
            isMe ? '${u.fullName} (tú)' : u.fullName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(Text(u.email)),
        DataCell(Text(u.role.label)),
        DataCell(
          u.active
              ? const StatusChip(
                  label: 'Activo',
                  color: AppColors.success,
                  icon: Icons.check_circle_outline,
                )
              : const StatusChip(
                  label: 'Inactivo',
                  color: AppColors.neutral,
                  icon: Icons.block,
                ),
        ),
        DataCell(
          Text(
            u.lastLoginAt == null
                ? 'Nunca'
                : Formatters.dateTime(u.lastLoginAt!),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Editar',
                onPressed: () => _openForm(user: u),
                icon: const Icon(Icons.edit_outlined),
              ),
              if (!isMe)
                TextButton(
                  onPressed: () => _toggleActive(u),
                  style: TextButton.styleFrom(
                    foregroundColor: u.active
                        ? AppColors.error
                        : AppColors.success,
                  ),
                  child: Text(u.active ? 'Desactivar' : 'Activar'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user});

  final ManagedUser? user;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user?.fullName);
  late final _email = TextEditingController(text: widget.user?.email);
  final _password = TextEditingController();
  late UserRole _role = widget.user?.role ?? UserRole.responsible;
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  bool get _isNew => widget.user == null;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Misma política que el backend: 8+ caracteres con letras y números.
  String? _validatePassword(String? v) {
    final p = v ?? '';
    if (p.isEmpty) return _isNew ? 'Ingresa una contraseña inicial.' : null;
    if (p.length < 8) return 'Al menos 8 caracteres.';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
      return 'Debe incluir letras y números.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<PanelApi>();
    final password = _password.text.isEmpty ? null : _password.text;
    try {
      if (_isNew) {
        await api.createUser(
          fullName: _name.text.trim(),
          email: _email.text.trim(),
          role: _role,
          password: password!,
        );
      } else {
        final u = widget.user!;
        final fullName = _name.text.trim() == u.fullName
            ? null
            : _name.text.trim();
        final role = _role == u.role ? null : _role;
        if (fullName == null && role == null && password == null) {
          if (mounted) Navigator.pop(context, false);
          return;
        }
        await api.updateUser(
          u.id,
          fullName: fullName,
          role: role,
          password: password,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Nuevo usuario' : 'Editar usuario'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                ),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Ingresa al menos 3 caracteres.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                enabled: _isNew,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico *',
                  helperText: _isNew ? null : 'El correo no se puede cambiar.',
                ),
                validator: (v) => _emailPattern.hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Correo electrónico no válido.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                isExpanded: true,
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rol *'),
                items: [
                  for (final r in UserRole.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                // El backend no permite cambiar el rol de la propia cuenta.
                onChanged: _saving || widget.user?.id == panelUser(context).id
                    ? null
                    : (r) => setState(() => _role = r!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: _isNew
                      ? 'Contraseña inicial *'
                      : 'Nueva contraseña',
                  helperText: _isNew
                      ? 'Mínimo 8 caracteres con letras y números.'
                      : 'Déjala vacía para mantener la actual.',
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? 'Mostrar contraseña'
                        : 'Ocultar contraseña',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: _validatePassword,
              ),
              if (!_isNew && _role != widget.user!.role)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Al cambiar el rol se cerrarán las sesiones abiertas del usuario.',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }
}
