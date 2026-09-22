import 'package:flutter/material.dart';

import '../models/checklist_template.dart';
import '../services/checklist_service.dart';
import '../storage/checklist_run_store.dart';
import '../storage/secure_store.dart';
import '../widgets/checklist_item_tile.dart';

/// Standalone equipment packing checklist — unrelated to shift open/close.
/// Two independent passes (HQ = packing, On-site = arrival verification)
/// against the same template, persisted locally so the run survives between
/// passes that may be hours or days apart. The On-site tab flags anything
/// checked at HQ but not yet confirmed On-site — that diff is the actual
/// mechanism that catches forgotten equipment.
class EquipmentChecklistScreen extends StatefulWidget {
  const EquipmentChecklistScreen({super.key, required this.header});

  final Widget header;

  @override
  State<EquipmentChecklistScreen> createState() =>
      _EquipmentChecklistScreenState();
}

// Standalone items get their own collapsible header, styled like a group's —
// this sentinel id (no real group ever has it) tracks its collapse state in
// the same set as real groups instead of needing a second bool.
const _standaloneGroupId = -1;

class _EquipmentChecklistScreenState extends State<EquipmentChecklistScreen>
    with SingleTickerProviderStateMixin {
  final _store = ChecklistRunStore();
  late final TabController _tabController;

  bool _isLoading = true;
  ChecklistTemplate? _template;
  ChecklistRunState _runState = ChecklistRunState.empty();
  final Set<int> _collapsedGroupIds = {};

  // Whether the user has explicitly asked to edit a pass that's already
  // fully resolved (and therefore normally locked). Resets to false the
  // moment that pass becomes fully resolved again, so "done" re-locks it.
  bool _homeUnlocked = false;
  bool _onsiteUnlocked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    const secureStore = SecureStore();
    final warehouseKey = await secureStore.readWarehouseId() ?? 'default';
    final token = await secureStore.readToken() ?? '';

    var template = await ChecklistService().fetchTemplate(token, 'equipment');
    if (template != null) {
      await _store.cacheTemplate(warehouseKey, template);
    } else {
      template = await _store.loadCachedTemplate(warehouseKey);
    }

    final runState = await _store.loadRunState();

    if (!mounted) return;
    setState(() {
      _template = template;
      _runState = runState;
      _isLoading = false;
    });
  }

  bool _isPassComplete(ChecklistPass pass, [ChecklistRunState? state]) {
    final template = _template;
    if (template == null || template.allItems.isEmpty) return false;
    final s = state ?? _runState;
    var sawVisibleItem = false;
    for (final item in template.allItems) {
      if (pass == ChecklistPass.onsite &&
          s.statusFor(ChecklistPass.home, item.id) == ChecklistItemStatus.excluded) {
        continue;
      }
      sawVisibleItem = true;
      if (s.statusFor(pass, item.id) == ChecklistItemStatus.unchecked) {
        return false;
      }
    }
    return sawVisibleItem;
  }

  bool _isPassLocked(ChecklistPass pass) {
    final unlocked = pass == ChecklistPass.home ? _homeUnlocked : _onsiteUnlocked;
    return _isPassComplete(pass) && !unlocked;
  }

  void _unlockPass(ChecklistPass pass) {
    setState(() {
      if (pass == ChecklistPass.home) {
        _homeUnlocked = true;
      } else {
        _onsiteUnlocked = true;
      }
    });
  }

  Future<void> _setStatus(
    ChecklistPass pass,
    int itemId,
    ChecklistItemStatus status,
  ) async {
    if (_isPassLocked(pass)) return;
    var updated = _runState.withItemStatus(pass, itemId, status, templateId: _template?.id);
    final nowComplete = _isPassComplete(pass, updated);
    updated = updated.withCompletion(pass, nowComplete);
    await _store.saveState(updated);
    if (!mounted) return;
    setState(() {
      _runState = updated;
      // Re-lock automatically once fully resolved again, even if this pass
      // had been explicitly unlocked to fix something.
      if (nowComplete) {
        if (pass == ChecklistPass.home) {
          _homeUnlocked = false;
        } else {
          _onsiteUnlocked = false;
        }
      }
    });
  }

  void _toggle(ChecklistPass pass, int itemId) {
    final current = _runState.statusFor(pass, itemId);
    final next = current == ChecklistItemStatus.checked
        ? ChecklistItemStatus.unchecked
        : ChecklistItemStatus.checked;
    _setStatus(pass, itemId, next);
  }

  void _exclude(ChecklistPass pass, int itemId) {
    final current = _runState.statusFor(pass, itemId);
    final next = current == ChecklistItemStatus.excluded
        ? ChecklistItemStatus.unchecked
        : ChecklistItemStatus.excluded;
    _setStatus(pass, itemId, next);
  }

  void _toggleGroupCollapsed(int groupId) {
    setState(() {
      if (_collapsedGroupIds.contains(groupId)) {
        _collapsedGroupIds.remove(groupId);
      } else {
        _collapsedGroupIds.add(groupId);
      }
    });
  }

  Future<void> _confirmStartNewRun() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start New Run?'),
        content: const Text(
          'This clears both the HQ and On-site checklists for a new event.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('START NEW'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.resetRun();
    if (!mounted) return;
    setState(() {
      _runState = ChecklistRunState.empty();
      _homeUnlocked = false;
      _onsiteUnlocked = false;
    });
  }

  List<int> _missingItemIds() {
    final template = _template;
    if (template == null) return [];
    final missing = <int>[];
    for (final item in template.allItems) {
      final home = _runState.statusFor(ChecklistPass.home, item.id);
      final onsite = _runState.statusFor(ChecklistPass.onsite, item.id);
      if (home == ChecklistItemStatus.checked &&
          onsite == ChecklistItemStatus.unchecked) {
        missing.add(item.id);
      }
    }
    return missing;
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final h = (local.hour % 12 == 0 ? 12 : local.hour % 12).toString();
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]}, $h:$m $ampm';
  }

  Widget _buildRunStatusBanner(ChecklistPass pass) {
    final locked = _isPassLocked(pass);
    final completedAt = _runState.completedAtFor(pass);
    final startedAt = _runState.startedAt;
    if (startedAt == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: locked ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: locked ? const Color(0xFFA5D6A7) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        children: [
          Icon(
            locked ? Icons.lock : Icons.play_circle_outline,
            size: 18,
            color: locked ? const Color(0xFF2E7D32) : const Color(0xFF757575),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Run started ${_formatTimestamp(startedAt)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
                ),
                if (locked && completedAt != null)
                  Text(
                    'Completed ${_formatTimestamp(completedAt)} — locked',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
              ],
            ),
          ),
          if (locked)
            TextButton(
              onPressed: () => _unlockPass(pass),
              child: const Text('EDIT'),
            ),
        ],
      ),
    );
  }

  // On the On-site pass, an item intentionally excluded at HQ isn't shown at
  // all — it was never going to be here, so leaving it in the list just
  // reads as an unexplained unchecked item. HQ still shows everything.
  bool _visibleForPass(ChecklistPass pass, ChecklistItem item) {
    if (pass != ChecklistPass.onsite) return true;
    return _runState.statusFor(ChecklistPass.home, item.id) !=
        ChecklistItemStatus.excluded;
  }

  Widget _buildPassList(ChecklistPass pass) {
    final template = _template!;
    final missingIds =
        pass == ChecklistPass.onsite ? _missingItemIds() : const <int>[];
    final locked = _isPassLocked(pass);

    Widget tileFor(ChecklistItem item) => ChecklistItemTile(
          item: item,
          status: _runState.statusFor(pass, item.id),
          onTap: locked ? () {} : () => _toggle(pass, item.id),
          onLongPress: locked ? () {} : () => _exclude(pass, item.id),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRunStatusBanner(pass),
          if (missingIds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF9A9A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline, size: 18, color: Color(0xFFC62828)),
                      SizedBox(width: 8),
                      Text(
                        'Possibly missing',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFC62828)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...template.allItems.where((i) => missingIds.contains(i.id)).map(
                        (i) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '• ${i.label}',
                            style: const TextStyle(color: Color(0xFFC62828)),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          for (final group in template.groups) ...[
            if (group.items.where((i) => _visibleForPass(pass, i)).isNotEmpty) ...[
              ChecklistGroupHeader(
                title: group.name,
                done: group.items
                    .where((i) => _visibleForPass(pass, i))
                    .where((i) =>
                        _runState.statusFor(pass, i.id) ==
                        ChecklistItemStatus.checked)
                    .length,
                total: group.items
                    .where((i) => _visibleForPass(pass, i))
                    .where((i) =>
                        _runState.statusFor(pass, i.id) !=
                        ChecklistItemStatus.excluded)
                    .length,
                collapsed: _collapsedGroupIds.contains(group.id),
                onToggle: () => _toggleGroupCollapsed(group.id),
              ),
              if (!_collapsedGroupIds.contains(group.id))
                ...group.items.where((i) => _visibleForPass(pass, i)).map(tileFor),
            ],
          ],
          if (template.standaloneItems.where((i) => _visibleForPass(pass, i)).isNotEmpty) ...[
            ChecklistGroupHeader(
              title: 'Standalone Items',
              done: template.standaloneItems
                  .where((i) => _visibleForPass(pass, i))
                  .where((i) =>
                      _runState.statusFor(pass, i.id) ==
                      ChecklistItemStatus.checked)
                  .length,
              total: template.standaloneItems
                  .where((i) => _visibleForPass(pass, i))
                  .where((i) =>
                      _runState.statusFor(pass, i.id) !=
                      ChecklistItemStatus.excluded)
                  .length,
              collapsed: _collapsedGroupIds.contains(_standaloneGroupId),
              onToggle: () => _toggleGroupCollapsed(_standaloneGroupId),
            ),
            if (!_collapsedGroupIds.contains(_standaloneGroupId))
              ...template.standaloneItems.where((i) => _visibleForPass(pass, i)).map(tileFor),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        widget.header,
        if (_isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_template == null || _template!.allItems.isEmpty)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No equipment checklist has been configured for your outlet yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9E9E9E)),
                ),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFFE67E22),
                    unselectedLabelColor: const Color(0xFF757575),
                    indicatorColor: const Color(0xFFE67E22),
                    tabs: const [Tab(text: 'HQ'), Tab(text: 'On-site')],
                  ),
                ),
                TextButton.icon(
                  onPressed: _confirmStartNewRun,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Start New Run'),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPassList(ChecklistPass.home),
                _buildPassList(ChecklistPass.onsite),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
