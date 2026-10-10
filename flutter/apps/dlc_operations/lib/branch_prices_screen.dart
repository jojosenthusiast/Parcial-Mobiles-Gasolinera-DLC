import 'package:dlc_api/dlc_api.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';

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
    } on DlcApiException catch (e) { _error = e.message; }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _propose() async {
    if (!widget.permissions.contains('price.propose')) return;
    if (_offers.isEmpty) { _message('Activa primero al menos un combustible de la sucursal.'); return; }
    final form = await _priceDialog(context, _offers);
    if (form == null || !mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.proposeFuelPrice(widget.branchId, fuelProductId: form.productId,
        serviceMode: form.serviceMode, price: form.price, effectiveAt: DateTime.now().add(const Duration(hours: 2)), reason: form.reason);
      await _load();
    } on DlcApiException catch (e) { if (mounted) setState(() { _error = e.message; _loading = false; }); }
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

  void _message(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Precios de combustible'), actions:[IconButton(onPressed:_loading?null:_load,tooltip:'Actualizar',icon:const Icon(Icons.refresh))]),
    floatingActionButton: widget.permissions.contains('price.propose') ? FloatingActionButton.extended(onPressed:_loading?null:_propose,icon:const Icon(Icons.add),label:const Text('Proponer precio')) : null,
    body: _loading ? const Center(child:CircularProgressIndicator()) : RefreshIndicator(onRefresh:_load, child:ListView(padding:const EdgeInsets.all(16),children:[
      if (_error != null) Card(color:context.dlc.criticalContainer,child:ListTile(leading:const Icon(Icons.error_outline),title:Text(_error!))),
      const Card(child:ListTile(leading:Icon(Icons.verified_user_outlined),title:Text('Aprobación independiente'),subtitle:Text('La persona que propone un precio no puede aprobarlo. Los precios requieren aprobación y programación antes de entrar en vigor.'))),
      const SizedBox(height:12),
      if (_proposals.isEmpty) const Card(child:ListTile(title:Text('Sin propuestas de precio'),subtitle:Text('Las propuestas aprobadas y programadas se reflejan en la preparación de la sucursal.'))),
      ..._proposals.map((row) {
        final status = _str(row['status']);
        final isMaker = _str(row['createdBy']) == _userId;
        final canApprove = status == 'pending_approval' && widget.permissions.contains('price.approve') && !isMaker;
        final canSchedule = status == 'approved' && widget.permissions.contains('price.apply');
        final actions = <Widget>[];
        if (canApprove) actions.add(TextButton.icon(onPressed:() => _approve(row),icon:const Icon(Icons.check),label:const Text('Aprobar')));
        if (status == 'pending_approval' && isMaker) actions.add(Padding(padding:EdgeInsets.all(8),child:Text('Requiere otra persona para aprobar',style:TextStyle(color:context.dlc.warning,fontSize:12))));
        if (canSchedule) actions.add(TextButton.icon(onPressed:() => _schedule(row),icon:const Icon(Icons.schedule),label:const Text('Programar')));
        final effective = DateTime.tryParse(_str(row['effectiveAt']))?.toLocal();
        final date = effective == null ? _str(row['effectiveAt']) : '${effective.day.toString().padLeft(2,'0')}/${effective.month.toString().padLeft(2,'0')} ${effective.hour.toString().padLeft(2,'0')}:${effective.minute.toString().padLeft(2,'0')}';
        return Card(margin:const EdgeInsets.only(bottom:8),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(_str(row['productName']),style:const TextStyle(fontWeight:FontWeight.w800))),Chip(label:Text(status))]),
          Text('\$${_str(row['priceUsdPerUnit'])} / ${_str(row['unit'])} · ${_str(row['serviceMode'])}'),
          Text('Vigencia: $date\n${_str(row['reason'])}',style:TextStyle(color:context.dlc.muted)),
          if(actions.isNotEmpty) Wrap(alignment:WrapAlignment.end,children:actions),
        ])));
      }),
    ])),
  );
}

class _PriceForm { const _PriceForm(this.productId,this.serviceMode,this.price,this.reason); final String productId,serviceMode,price,reason; }
Future<_PriceForm?> _priceDialog(BuildContext context,List<Map<String,dynamic>> offers) async {
  String productId=_str(offers.first['fuelProductId']), mode='full_service';
  final price=TextEditingController(), reason=TextEditingController();
  final result=await showDialog<_PriceForm>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setState)=>AlertDialog(
    title:const Text('Proponer precio por litro'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<String>(initialValue:productId,decoration:const InputDecoration(labelText:'Combustible'),items:offers.map((o)=>DropdownMenuItem(value:_str(o['fuelProductId']),child:Text(_str(o['fuelName']??o['productName']??o['fuelProductId']),overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>productId=v??productId)),
      const SizedBox(height:8),DropdownButtonFormField<String>(initialValue:mode,decoration:const InputDecoration(labelText:'Modalidad'),items:const[DropdownMenuItem(value:'full_service',child:Text('Servicio completo')),DropdownMenuItem(value:'self_service',child:Text('Autoservicio'))],onChanged:(v)=>setState(()=>mode=v??mode)),
      const SizedBox(height:8),TextField(controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Precio USD por litro')),
      const SizedBox(height:8),TextField(controller:reason,minLines:2,maxLines:3,maxLength:500,decoration:const InputDecoration(labelText:'Motivo de la propuesta')),
      Text('La propuesta queda pendiente y otra persona autorizada debe aprobarla.',style:TextStyle(fontSize:12,color:context.dlc.muted)),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Volver')),FilledButton(onPressed:()=>Navigator.pop(context,_PriceForm(productId,mode,price.text.trim(),reason.text.trim())),child:const Text('Enviar propuesta'))],
  )));
  price.dispose();reason.dispose();
  if(result==null)return null;
  if(result.price.isEmpty||result.reason.isEmpty) return null;
  return result;
}
String _str(dynamic value)=>value?.toString()??'';
int _int(dynamic value)=>int.tryParse('$value')??1;
