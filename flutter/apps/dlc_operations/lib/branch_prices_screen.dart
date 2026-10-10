import 'package:dlc_api/dlc_api.dart';
import 'app_theme.dart';
import 'format.dart';
import 'labels.dart';
import 'ui/prices_page.dart' show showPriceProposalSheet;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

class BranchPricesScreen extends StatefulWidget {
  const BranchPricesScreen({required this.api, required this.branchId, required this.permissions, super.key});
  final EmployeeSession api;
  final String branchId;
  final Set<String> permissions;
  @override State<BranchPricesScreen> createState() => _BranchPricesScreenState();
}

class _BranchPricesScreenState extends State<BranchPricesScreen> {
  List<Map<String, dynamic>> _offers = const [], _proposals = const [];
  String? _userId, _error;
  BranchSummary? _branch;
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final values = await Future.wait<dynamic>([
        widget.api.branchConfiguration(widget.branchId),
        widget.api.fuelPriceProposals(widget.branchId),
        widget.api.currentIdentity(),
      ]);
      final config = values[0] as Map<String, dynamic>;
      _offers = (config['fuelOffers'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>()
          .where((row) => row['status'] == 'active').map((row) => Map<String, dynamic>.from(row)).toList();
      _proposals = values[1] as List<Map<String, dynamic>>;
      _userId = (values[2] as EmployeeIdentity).id;
      _branch = BranchSummary.fromJson(values[3] as Map<String, dynamic>);
    } on DlcApiException catch (e) { _error = e.message; }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _propose() async {
    if (!widget.permissions.contains('price.propose')) return;
    final branch = _branch ?? BranchSummary(id: widget.branchId, code: '', name: 'Sucursal', zone: 'central', timezone: 'America/El_Salvador');
    final done = await showPriceProposalSheet(context, api: widget.api, branch: branch, offers: _offers);
    if (done == true) await _load();
  }
  Future<void> _approve(Map<String, dynamic> row) async {
    await _mutate(() => widget.api.decideFuelPrice(_str(row['id']), _int(row['version'])));
  }
  Future<void> _schedule(Map<String, dynamic> row) async {
    await _mutate(() => widget.api.scheduleFuelPrice(_str(row['id']), _int(row['version'])));
  }
  Future<void> _mutate(Future<dynamic> Function() action) async {
    setState(() { _loading = true; _error = null; });
    try { await action(); await _load(); }
    on DlcApiException catch (e) { if (mounted) setState(() { _error = e.message; _loading = false; }); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Precios de combustible'), actions:[IconButton(onPressed:_loading?null:_load,tooltip:'Actualizar',icon:const Icon(CupertinoIcons.refresh))]),
    floatingActionButton: widget.permissions.contains('price.propose') ? FloatingActionButton.extended(onPressed:_loading?null:_propose,icon:const Icon(CupertinoIcons.add),label:const Text('Proponer precio')) : null,
    body: _loading ? const Center(child:CircularProgressIndicator()) : RefreshIndicator(onRefresh:_load, child:ListView(padding:const EdgeInsets.all(16),children:[
      if (_error != null) Card(color:context.dlc.criticalContainer,child:ListTile(leading:const Icon(CupertinoIcons.exclamationmark_circle),title:Text(_error!))),
      const Card(child:ListTile(leading:Icon(CupertinoIcons.checkmark_shield),title:Text('Aprobación independiente'),subtitle:Text('La persona que propone un precio no puede aprobarlo. Los precios requieren aprobación y programación antes de entrar en vigor.'))),
      const SizedBox(height:12),
      if (_proposals.isEmpty) const Card(child:ListTile(title:Text('Sin propuestas de precio'),subtitle:Text('Las propuestas aprobadas y programadas se reflejan en la preparación de la sucursal.'))),
      ..._proposals.map((row) {
        final status = _str(row['status']);
        final isMaker = _str(row['createdBy']) == _userId;
        final canApprove = status == 'pending_approval' && widget.permissions.contains('price.approve') && !isMaker;
        final canSchedule = status == 'approved' && widget.permissions.contains('price.apply');
        final actions = <Widget>[];
        if (canApprove) actions.add(TextButton.icon(onPressed:() => _approve(row),icon:const Icon(CupertinoIcons.checkmark_alt),label:const Text('Aprobar')));
        if (status == 'pending_approval' && isMaker) actions.add(Padding(padding:EdgeInsets.all(8),child:Text('Requiere otra persona para aprobar',style:TextStyle(color:context.dlc.warning,fontSize:12))));
        if (canSchedule) actions.add(TextButton.icon(onPressed:() => _schedule(row),icon:const Icon(CupertinoIcons.clock),label:const Text('Programar')));
        final effective = DateTime.tryParse(_str(row['effectiveAt']))?.toLocal();
        final date = effective == null ? _str(row['effectiveAt']) : '${effective.day.toString().padLeft(2,'0')}/${effective.month.toString().padLeft(2,'0')} ${effective.hour.toString().padLeft(2,'0')}:${effective.minute.toString().padLeft(2,'0')}';
        return Card(margin:const EdgeInsets.only(bottom:8),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(_str(row['productName']),style:const TextStyle(fontWeight:FontWeight.w800))),StatusBadge(status)]),
          Text('${moneyRaw(row['priceUsdPerUnit'], decimals: 4)} / ${unitLabel(row['unit'])} · ${serviceModeLabel(row['serviceMode'])}'),
          Text('Vigencia: $date\n${_str(row['reason'])}',style:TextStyle(color:context.dlc.muted)),
          if(actions.isNotEmpty) Wrap(alignment:WrapAlignment.end,children:actions),
        ])));
      }),
    ])),
  );
}

String _str(dynamic value)=>value?.toString()??'';
int _int(dynamic value)=>int.tryParse('$value')??1;
