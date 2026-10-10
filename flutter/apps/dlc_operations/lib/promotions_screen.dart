import 'dart:math';
import 'app_theme.dart';
import 'dart:typed_data';

import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';
import 'labels.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:image_picker/image_picker.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({required this.api, required this.branchId, required this.branchTimeZone, required this.permissions, super.key});
  final EmployeeSession api;
  final String? branchId;
  final String branchTimeZone;
  final Set<String> permissions;
  @override State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  List<Map<String, dynamic>> rows = const [];
  List<BranchSummary> branchCatalog = const [];
  bool loading = true, busy = false;
  String? error;
  bool get canCreate => widget.permissions.contains('promotion.manage') || widget.permissions.contains('promotion.network.manage');
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      rows = await widget.api.promotions(branchId: widget.branchId);
      if(widget.permissions.contains('promotion.network.manage')||widget.permissions.contains('promotion.network.approve')) branchCatalog=await widget.api.branches();
    }
    on DlcApiException catch (e) { error = e.message; }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _create() async {
    List<BranchSummary> availableBranches = branchCatalog;
    if (widget.permissions.contains('promotion.network.manage')) {
      try { availableBranches = (await widget.api.branches()).where((branch) => branch.status == 'active').toList(); }
      on DlcApiException catch (e) { setState(() => error = e.message); return; }
    }
    final result = await Navigator.push<bool>(context, MaterialPageRoute<bool>(builder: (_) => PromotionEditorPage(
      api: widget.api, branchId: widget.branchId, branchTimeZone: widget.branchTimeZone,
      branches: availableBranches,
      allowNetwork: widget.permissions.contains('promotion.network.manage'),
      allowBranch: widget.permissions.contains('promotion.manage'),
    )));
    if (result == true && mounted) await _load();
  }

  Future<void> _addCashbackBank() async {
    final code = TextEditingController(), name = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Agregar banco participante'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: code, maxLength: 40, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Código corto único', helperText: 'Usa el código oficial acordado para esta organización.')), TextField(controller: name, maxLength: 120, decoration: const InputDecoration(labelText: 'Nombre visible'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar'))]));
    final codeValue = code.text.trim(), nameValue = name.text.trim(); code.dispose(); name.dispose();
    if (result != true) return;
    if (codeValue.length < 2 || nameValue.length < 2) { setState(() => error = 'Completa un código y nombre válidos.'); return; }
    await _action(() => widget.api.createCashbackPartner(codeValue, nameValue));
  }

  Future<void> _action(Future<Map<String, dynamic>> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try { await action(); await _load(); }
    on DlcApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _review(Map<String, dynamic> item, String decision) async {
    final reason = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(decision == 'approve' ? 'Aprobar promoción' : 'Rechazar promoción'),
      content: TextField(controller: reason, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Motivo de revisión', helperText: 'Mínimo 10 caracteres. La decisión queda auditada.')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, reason.text.trim()), child: const Text('Continuar'))],
    ));
    final text = reason.text.trim(); reason.dispose();
    if (result == null) return;
    if (text.length < 10) { setState(() => error = 'Explica la decisión con al menos 10 caracteres.'); return; }
    await _action(() => widget.api.decidePromotion(_str(item['id']), decision, text));
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Promociones')),
    floatingActionButton: canCreate ? FloatingActionButton.extended(onPressed: busy ? null : _create, icon: const Icon(CupertinoIcons.add), label: const Text('Nueva promoción')) : null,
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
      const Text('Beneficios y anuncios', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const Padding(padding: EdgeInsets.only(top: 6, bottom: 12), child: Text('Los borradores no se muestran a Clientes. Las reglas económicas requieren aprobación de otra persona.')),
      if (widget.permissions.contains('promotion.network.manage')) Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: busy ? null : _addCashbackBank, icon: const Icon(CupertinoIcons.house), label: const Text('Configurar bancos cashback'))),
      if (error != null) Card(color: context.dlc.criticalContainer, child: ListTile(leading: const Icon(CupertinoIcons.exclamationmark_circle), title: Text(error!))),
      if (rows.isEmpty) const Card(child: ListTile(leading: Icon(CupertinoIcons.bell), title: Text('Aún no hay promociones en este ámbito.'))),
      ...rows.map(_promotionTile),
      if (busy) const LinearProgressIndicator(),
    ])),
  );

  Widget _promotionTile(Map<String, dynamic> item) {
    final id = _str(item['id']), status = _str(item['status']), versionStatus = _str(item['versionStatus']);
    final definition = item['definition'] is Map ? Map<String, dynamic>.from(item['definition'] as Map) : const <String, dynamic>{};
    final metric = _map(definition['targetMetric']);
    final targetIds = _lines(definition['targetBranchIds']);
    final zones = _lines(definition['targetZones']);
    final metricBranches = metric['includedBranches'] is List ? (metric['includedBranches'] as List).length : 0;
    final metricRows = metric['includedBranches'] is List ? (metric['includedBranches'] as List).whereType<Map>().map((row)=>Map<String,dynamic>.from(row)).toList() : const <Map<String,dynamic>>[];
    final canReview = widget.permissions.contains('promotion.network.approve');
    final actions = <Widget>[];
    if (versionStatus == 'draft' && (widget.permissions.contains(item['scope'] == 'network' ? 'promotion.network.manage' : 'promotion.manage'))) {
      actions.add(TextButton(onPressed: busy ? null : () => _action(() => widget.api.submitPromotion(id)), child: const Text('Enviar a revisión')));
    }
    if (versionStatus == 'pending_approval' && canReview) {
      actions.add(TextButton(onPressed: busy ? null : () => _review(item, 'reject'), child: const Text('Rechazar')));
      actions.add(FilledButton(onPressed: busy ? null : () => _review(item, 'approve'), child: const Text('Revisar y aprobar')));
    }
    if (['active', 'scheduled'].contains(status) && canReview) actions.add(TextButton(onPressed: busy ? null : () => _pause(id), child: const Text('Suspender')));
    if (status == 'paused' && canReview) actions.add(TextButton(onPressed: busy ? null : () => _action(() => widget.api.resumePromotion(id)), child: const Text('Reanudar')));
    return Card(margin: const EdgeInsets.only(bottom: 12), clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_str(definition['imageUrl']).isNotEmpty) Image.network(_str(definition['imageUrl']), height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 70, child: Center(child: Icon(CupertinoIcons.photo)))),
      Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(_str(definition['title']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), Row(mainAxisSize: MainAxisSize.min, children: [StatusBadge(status, compact: true), Text(' v${item['currentVersion'] ?? 1}')])]),
        Text(_headline(definition), style: TextStyle(color: context.dlc.brand, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4), Text(_str(definition['motive'])),
        Text('${_str(definition['startsAt'])} – ${_str(definition['endsAt'])} · ${_str(definition['timeZone'])}', style: TextStyle(fontSize: 12, color: context.dlc.muted)),
        if(item['scope']=='network') Text('Audiencia: ${targetIds.isEmpty?'toda la red': '${targetIds.length} sucursales'}${zones.isEmpty?'':' · zonas ${zones.join(', ')}'}',style:TextStyle(fontSize:12,color:context.dlc.muted)),
        if(metric.isNotEmpty) Text('Criterio congelado: ${metric['metric']} ≥ ${metric['threshold']} · corte ${_str(metric['asOf'])} · $metricBranches sucursales cumplen',style:TextStyle(fontSize:12,color:context.dlc.muted)),
        if(metricRows.isNotEmpty) ExpansionTile(title:const Text('Ver sucursales incluidas y medición'),tilePadding:EdgeInsets.zero,children:metricRows.map((row){final id=_str(row['branchId']);final branch=branchCatalog.where((b)=>b.id==id).firstOrNull;return ListTile(dense:true,title:Text(branch?.name??id),subtitle:Text('${branch?.zone??''} · ${_str(row['observedValue'])}'),);}).toList()),
        Text('Condiciones: ${_lines(_map(definition['terms'])['applies']).join(' · ')}', maxLines: 2, overflow: TextOverflow.ellipsis),
        if (actions.isNotEmpty) Wrap(alignment: WrapAlignment.end, spacing: 6, children: actions),
      ])),
    ]));
  }

  Future<void> _pause(String id) async {
    final reason = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('Suspender promoción'), content: TextField(controller: reason, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Motivo (mínimo 10 caracteres)')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')), FilledButton(onPressed: () => Navigator.pop(context, reason.text.trim()), child: const Text('Suspender'))]));
    final text = reason.text.trim(); reason.dispose();
    if (result == null) return;
    if (text.length < 10) { setState(() => error = 'Explica por qué suspendes esta promoción.'); return; }
    await _action(() => widget.api.pausePromotion(id, text));
  }
}

class PromotionEditorPage extends StatefulWidget {
  const PromotionEditorPage({required this.api, required this.branchId, required this.branchTimeZone, required this.branches, required this.allowNetwork, required this.allowBranch, super.key});
  final EmployeeSession api; final String? branchId; final String branchTimeZone; final bool allowNetwork; final bool allowBranch;
  final List<BranchSummary> branches;
  @override State<PromotionEditorPage> createState() => _PromotionEditorPageState();
}

class _PromotionEditorPageState extends State<PromotionEditorPage> {
  final title = TextEditingController(), motive = TextEditingController(), value = TextEditingController(), cap = TextEditingController(), minimum = TextEditingController(), budget = TextEditingController(), uses = TextEditingController(), imageAlt = TextEditingController(), applies = TextEditingController(), excludes = TextEditingController(), productIds = TextEditingController(), targetThreshold = TextEditingController();
  final ImagePicker imagePicker = ImagePicker();
  String? imageUrl;
  String? imageUploadCommandId;
  Uint8List? pendingImageBytes;
  String? pendingImageMime;
  List<Map<String, dynamic>> banks = const [];
  String? bankCode;
  String kind = 'unit_discount', recurrence = 'once', scope = 'branch', stacking = 'none', targetMetric = 'none';
  String? selectedTimeZone;
  String valueUnit = 'us_gallon';
  DateTime start = DateTime.now().add(const Duration(days: 1)), end = DateTime.now().add(const Duration(days: 30));
  int monthlyDay = 20, priority = 10;
  final Set<int> weekdays = {3};
  final Set<String> targetBranchIds = {}, targetZones = {};
  bool busy = false, previewed = false, uploadingImage = false;
  bool termsAcknowledged = false;
  String? error, previewText;
  String get campaignTimeZone {
    if(scope=='branch') return widget.branchTimeZone;
    if(selectedTimeZone!=null) return selectedTimeZone!;
    final filtered=targetBranchIds.isEmpty&&targetZones.isEmpty?widget.branches:widget.branches.where((branch)=>targetBranchIds.contains(branch.id)||targetZones.contains(branch.zone));
    final values=filtered.map((branch)=>branch.timezone).toSet();
    return values.length==1?values.first:widget.branches.firstOrNull?.timezone??widget.branchTimeZone;
  }
  @override void initState() { super.initState(); if (widget.allowNetwork && !widget.allowBranch) scope = 'network'; _loadBanks(); }
  Future<void> _loadBanks() async { try { final result = await widget.api.cashbackPartners(); if (mounted) setState(() => banks = result.where((row)=>row['status']=='active').toList()); } on DlcApiException catch (e) { if (mounted) setState(() => error = e.message); } }
  @override void dispose() { for (final c in [title,motive,value,cap,minimum,budget,uses,imageAlt,applies,excludes,productIds,targetThreshold]) { c.dispose(); } super.dispose(); }

  Map<String, dynamic>? _definition() {
    final needsImage = imageUrl != null;
    if (title.text.trim().length < 3 || motive.text.trim().length < 10) { setState(() => error = 'El título necesita 3 caracteres y el motivo al menos 10.'); return null; }
    final appliesTerms = applies.text.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final excludesTerms = excludes.text.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (appliesTerms.isEmpty || appliesTerms.length > 20 || appliesTerms.any((x) => x.length < 5 || x.length > 300) || excludesTerms.length > 20 || excludesTerms.any((x) => x.length < 5 || x.length > 300)) { setState(() => error = 'Agrega de 1 a 20 condiciones aplicables y revisa que cada condición tenga entre 5 y 300 caracteres.'); return null; }
    if (!termsAcknowledged) { setState(() => error = 'Confirma que revisaste y completaste las condiciones de la promoción.'); return null; }
    if (scope=='network' && targetMetric!='none' && ((double.tryParse(targetThreshold.text.trim())??0)<=0)) { setState(() => error = 'Indica un umbral estadístico mayor que cero.'); return null; }
    if (needsImage && imageAlt.text.trim().length < 5) { setState(() => error = 'Describe la imagen para lectores de pantalla.'); return null; }
    if (kind != 'announcement' && value.text.trim().isEmpty) { setState(() => error = 'El beneficio requiere un valor.'); return null; }
    if (kind == 'cashback' && (bankCode == null || !banks.any((row)=>row['code']==bankCode) || cap.text.trim().isEmpty)) { setState(() => error = 'El cashback requiere un banco activo configurado y un tope por operación.'); return null; }
    if (uses.text.trim().isNotEmpty && (int.tryParse(uses.text.trim()) == null || int.parse(uses.text.trim()) < 1 || int.parse(uses.text.trim()) > 1000)) { setState(() => error = 'El límite por cliente debe ser un entero entre 1 y 1000.'); return null; }
    if (recurrence == 'weekly' && weekdays.isEmpty) { setState(() => error = 'Selecciona al menos un día de semana.'); return null; }
    final result = <String, dynamic>{
      'scope': scope, if (scope == 'branch') 'branchId': widget.branchId,
      if (scope == 'network' && targetBranchIds.isNotEmpty) 'targetBranchIds': targetBranchIds.toList()..sort(),
      if (scope == 'network' && targetZones.isNotEmpty) 'targetZones': targetZones.toList()..sort(),
      if (scope == 'network' && targetMetric != 'none') 'targetMetric': {'metric':targetMetric,'threshold':targetThreshold.text.trim()},
      'title': title.text.trim(), 'motive': motive.text.trim(), 'kind': kind,
      'startsAt': _dateLabel(start), 'endsAt': _dateLabel(end),
      'timeZone': campaignTimeZone,
      'recurrence': recurrence == 'weekly' ? {'kind':'weekly','weekdays':weekdays.toList()..sort()} : recurrence == 'monthly' ? {'kind':'monthly','dayOfMonth':monthlyDay} : {'kind':'once'},
      if (productIds.text.trim().isNotEmpty) 'productIds': productIds.text.split(',').map((x)=>x.trim()).where((x)=>x.isNotEmpty).toList(),
      if (kind == 'unit_discount') ...{'value':value.text.trim(),'valueUnit':valueUnit},
      if (kind == 'percent_discount' || kind == 'points_multiplier') 'value':value.text.trim(),
      if (kind == 'cashback') ...{'value':value.text.trim(),'bankCode':bankCode,'benefitCapUsd':cap.text.trim()},
      if (minimum.text.trim().isNotEmpty) 'minimumSpendUsd':minimum.text.trim(),
      if (budget.text.trim().isNotEmpty) 'totalBudgetUsd':budget.text.trim(),
      if (uses.text.trim().isNotEmpty) 'maxUsesPerCustomer':int.tryParse(uses.text.trim()),
      'priority':priority, 'stacking':kind == 'points_multiplier' ? 'none' : stacking,
      'terms':{'applies':appliesTerms,'excludes':excludesTerms},
      if (needsImage) ...{'imageUrl':imageUrl,'imageAlt':imageAlt.text.trim()},
    };
    if (scope == 'branch' && widget.branchId == null) { setState(() => error = 'Selecciona una sucursal antes de crear la promoción.'); return null; }
    return result;
  }

  Future<void> _preview() async {
    final data = _definition(); if (data == null) return;
    setState(() { busy = true; error = null; previewText = null; });
    try {
      final result = await widget.api.previewPromotion(data);
      final dates = (result['occurrences'] as List<dynamic>? ?? const []).join('\n');
      final audience=_map(result['targeting']);
      final branchIds=_lines(audience['branchIds']);
      final metric=_map(audience['metric']);
      final metricValues=metric['includedBranches'] is List ? (metric['includedBranches'] as List).length : null;
      final targetText=audience.isEmpty?'':'\nAudiencia congelada: ${branchIds.length} sucursales${metricValues==null?'':' · $metricValues cumplen el umbral'}';
      if (mounted) setState(() { previewed = true; previewText = '${dates.isEmpty ? 'No hay ocurrencias en este rango.' : 'Próximas fechas:\n$dates'}$targetText'; });
    }
    on DlcApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _save() async {
    final data = _definition(); if (data == null) return;
    if (!previewed) { setState(() => error = 'Previsualiza y verifica las fechas antes de guardar.'); return; }
    setState(() { busy = true; error = null; });
    try { await widget.api.createPromotion(data); if (mounted) Navigator.pop(context, true); }
    on DlcApiException catch (e) { if (mounted) setState(() => error = e.message); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _pickPromotionImage() async {
    try {
      if (pendingImageBytes == null) {
        final file = await imagePicker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
        if (file == null || !mounted) return;
        final bytes = await file.readAsBytes();
        if (bytes.length > 1048576) throw const DlcApiException('La imagen supera 1 MB. Elige una imagen más pequeña.');
        final name = file.name.toLowerCase();
        final mimeType = file.mimeType ?? (name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
        if (!['image/jpeg','image/png','image/webp'].contains(mimeType)) throw const DlcApiException('Usa una imagen JPG, PNG o WebP.');
        setState(() { pendingImageBytes = bytes; pendingImageMime = mimeType; imageUploadCommandId = _promotionCommandId(); });
      }
      setState(() { uploadingImage = true; error = null; });
      final commandId = imageUploadCommandId!;
      final uploaded = await widget.api.uploadPromotionImage(pendingImageBytes!, pendingImageMime!, commandId: commandId, scope: scope, branchId: scope == 'branch' ? widget.branchId : null);
      if (mounted) setState(() { imageUrl = _str(uploaded['imageUrl']); pendingImageBytes = null; pendingImageMime = null; previewed = false; });
    } on DlcApiException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'No se pudo seleccionar o cargar la imagen.'); }
    finally { if (mounted) setState(() => uploadingImage = false); }
  }

  Future<void> _date(bool isStart) async {
    final selected = await showDatePicker(context: context, initialDate: isStart ? start : end, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (selected != null) setState(() { if (isStart) { start = selected; if (end.isBefore(start)) end = start.add(const Duration(days:1)); } else { end = selected; } previewed = false; });
  }

  Widget _audienceSelector() {
    const zones = <String, String>{'occidental':'Occidente','central':'Centro','oriental':'Oriente','other':'Otras'};
    return Card(margin: const EdgeInsets.only(top:12), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Sucursales objetivo', style: TextStyle(fontWeight: FontWeight.w800)),
      const Text('Sin filtros, la campaña incluye las sucursales activas actuales. Si eliges zonas y sucursales, se combinan.'),
      Wrap(spacing:6, children: zones.entries.map((entry) => FilterChip(label:Text(entry.value), selected:targetZones.contains(entry.key), onSelected:(selected) {
        setState(() { if (selected) { targetZones.add(entry.key); } else { targetZones.remove(entry.key); } previewed=false; });
      })).toList()),
      const Divider(),
      if(widget.branches.isEmpty) const Text('No hay sucursales activas para seleccionar.'),
      ...widget.branches.map((branch)=>CheckboxListTile(contentPadding:EdgeInsets.zero,dense:true,value:targetBranchIds.contains(branch.id),title:Text('${branch.name} · ${zones[branch.zone]??branch.zone}'),subtitle:Text(branch.timezone),onChanged:(selected) {
        setState(() { if (selected==true) { targetBranchIds.add(branch.id); } else { targetBranchIds.remove(branch.id); } previewed=false; });
      })),
    ])));
  }

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Nueva promoción')), body: ListView(padding: const EdgeInsets.all(18), children: [
    Text('Prepara el borrador. Nada se publica hasta que otra persona revise y apruebe la regla. Los anuncios informativos pueden publicarse; los descuentos, cashback y multiplicadores siguen bloqueados hasta conectarse al cobro/POS y a la acreditación de puntos.', style: TextStyle(color: context.dlc.muted)),
    if (error != null) Card(color: context.dlc.criticalContainer, child: ListTile(leading: const Icon(CupertinoIcons.exclamationmark_circle), title: Text(error!))),
    if (widget.allowNetwork && widget.allowBranch) DropdownButtonFormField<String>(initialValue: scope, decoration: const InputDecoration(labelText:'Alcance'), items: const [DropdownMenuItem(value:'branch',child:Text('Una sucursal')),DropdownMenuItem(value:'network',child:Text('Toda la red'))], onChanged:(v) { setState(() { scope=v??scope; imageUrl=null; imageUploadCommandId=null; pendingImageBytes=null; pendingImageMime=null; previewed=false; }); }),
    if(scope=='network') _audienceSelector(),
    if(scope=='network' && widget.branches.map((branch)=>branch.timezone).toSet().length>1) DropdownButtonFormField<String>(initialValue:campaignTimeZone,decoration:const InputDecoration(labelText:'Zona horaria para fechas y recurrencias'),items:widget.branches.map((branch)=>branch.timezone).toSet().map((zone)=>DropdownMenuItem(value:zone,child:Text(zone))).toList(),onChanged:(zone) { setState(() { selectedTimeZone=zone; previewed=false; }); }),
    if(scope=='network') ...[
      DropdownButtonFormField<String>(initialValue:targetMetric,decoration:const InputDecoration(labelText:'Filtro estadístico opcional'),items:const [DropdownMenuItem(value:'none',child:Text('Sin filtro estadístico')),DropdownMenuItem(value:'sales_usd_30d',child:Text('Ventas pagadas últimos 30 días (USD)')),DropdownMenuItem(value:'fuel_liters_30d',child:Text('Litros de combustible últimos 30 días'))],onChanged:(v) { setState(() { targetMetric=v??targetMetric; previewed=false; }); }),
      if(targetMetric!='none') _field(targetThreshold,targetMetric=='sales_usd_30d'?'Umbral mínimo de venta en USD':'Umbral mínimo de litros vendidos',keyboard:const TextInputType.numberWithOptions(decimal:true)),
    ],
    _field(title,'Título de la promoción',max:120), _field(motive,'Motivo y resumen claro',max:500,maxLines:3),
    DropdownButtonFormField<String>(initialValue:kind,decoration:const InputDecoration(labelText:'Tipo de beneficio'),items:const [DropdownMenuItem(value:'unit_discount',child:Text('Descuento por litro/galón')),DropdownMenuItem(value:'percent_discount',child:Text('Descuento porcentual')),DropdownMenuItem(value:'cashback',child:Text('Cashback de banco')),DropdownMenuItem(value:'points_multiplier',child:Text('Puntos dobles/triples')),DropdownMenuItem(value:'announcement',child:Text('Anuncio informativo'))],onChanged:(v) { setState(() { kind=v??kind; previewed=false; }); }),
    if(kind=='unit_discount'||kind=='percent_discount'||kind=='cashback'||kind=='points_multiplier') _field(value,kind=='cashback'?'Porcentaje de cashback':kind=='points_multiplier'?'Multiplicador entero (ej. 2 o 3)':kind=='percent_discount'?'Porcentaje de descuento':'Descuento por unidad',keyboard:const TextInputType.numberWithOptions(decimal:true)),
    if(kind=='unit_discount') DropdownButtonFormField<String>(initialValue:valueUnit,decoration:const InputDecoration(labelText:'Unidad del descuento'),items:const [DropdownMenuItem(value:'us_gallon',child:Text('Galón estadounidense')),DropdownMenuItem(value:'liter',child:Text('Litro'))],onChanged:(v) { setState(() { valueUnit=v??valueUnit; previewed=false; }); }),
    if(kind=='cashback') ...[DropdownButtonFormField<String>(initialValue:bankCode,decoration:const InputDecoration(labelText:'Banco participante'),items:banks.map((row)=>DropdownMenuItem<String>(value:_str(row['code']),child:Text(_str(row['displayName'])))).toList(),onChanged:(v) { setState(() { bankCode=v; previewed=false; }); }),if(banks.isEmpty)const Text('No hay bancos activos configurados por Gerencia General.'),_field(cap,'Tope de cashback por operación USD',keyboard:const TextInputType.numberWithOptions(decimal:true))],
    _field(minimum,'Compra mínima USD (opcional)',keyboard:const TextInputType.numberWithOptions(decimal:true)),_field(budget,'Presupuesto máximo de la campaña USD (opcional)',keyboard:const TextInputType.numberWithOptions(decimal:true)),_field(uses,'Usos máximos por cliente (opcional)',keyboard:TextInputType.number),
    _field(productIds,'IDs de producto separados por coma (vacío = todos)',max:1500,maxLines:2),
    DropdownButtonFormField<String>(initialValue:recurrence,decoration:const InputDecoration(labelText:'Frecuencia'),items:const [DropdownMenuItem(value:'once',child:Text('Una sola vigencia')),DropdownMenuItem(value:'weekly',child:Text('Días específicos de la semana')),DropdownMenuItem(value:'monthly',child:Text('Día específico de cada mes'))],onChanged:(v) { setState(() { recurrence=v??recurrence; previewed=false; }); }),
    if(recurrence=='weekly') Wrap(spacing:4,children:List.generate(7,(day){const labels=['Do','Lu','Ma','Mi','Ju','Vi','Sá'];return FilterChip(label:Text(labels[day]),selected:weekdays.contains(day),onSelected:(yes) { setState(() { if (yes) { weekdays.add(day); } else { weekdays.remove(day); } previewed=false; }); });})),
    if(recurrence=='monthly') DropdownButtonFormField<int>(initialValue:monthlyDay,decoration:const InputDecoration(labelText:'Día del mes (si no existe, se omite)'),items:List.generate(31,(i)=>DropdownMenuItem(value:i+1,child:Text('${i+1}'))),onChanged:(v) { setState(() { monthlyDay=v??monthlyDay; previewed=false; }); }),
    Row(children:[Expanded(child:OutlinedButton.icon(onPressed:busy?null:()=>_date(true),icon:const Icon(CupertinoIcons.calendar),label:Text('Inicio ${_dateLabel(start)}'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:busy?null:()=>_date(false),icon:const Icon(CupertinoIcons.calendar),label:Text('Fin ${_dateLabel(end)}')))]),
    Text('Zona horaria de la audiencia: $campaignTimeZone',style:TextStyle(color:context.dlc.muted)),
    if(kind!='announcement') DropdownButtonFormField<String>(initialValue:stacking,decoration:const InputDecoration(labelText:'Combinación con puntos'),items:const [DropdownMenuItem(value:'none',child:Text('No combinar')),DropdownMenuItem(value:'with_points',child:Text('Permitir junto con puntos'))],onChanged:(v) { setState(() { stacking=v??stacking; previewed=false; }); }),
    const Padding(padding:EdgeInsets.only(top:14,bottom:4),child:Text('Imagen de promoción',style:TextStyle(fontWeight:FontWeight.w700))),
    OutlinedButton.icon(onPressed:busy||uploadingImage?null:_pickPromotionImage,icon:uploadingImage?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(CupertinoIcons.photo),label:Text(uploadingImage?'Cargando imagen…':pendingImageBytes!=null?'Reintentar carga':imageUrl==null?'Seleccionar imagen':'Cambiar imagen')),
    if(pendingImageBytes!=null&&!uploadingImage) TextButton(onPressed:() { setState(() { pendingImageBytes=null; pendingImageMime=null; imageUploadCommandId=null; }); },child:const Text('Descartar imagen pendiente')),
    if(imageUrl!=null) ...[ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.network(imageUrl!,height:150,width:double.infinity,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox(height:70,child:Center(child:Icon(CupertinoIcons.photo))))),TextButton.icon(onPressed:busy||uploadingImage?null:() { setState(() { imageUrl=null; imageUploadCommandId=null; previewed=false; }); },icon:const Icon(CupertinoIcons.trash),label:const Text('Quitar imagen')),_field(imageAlt,'Texto alternativo de la imagen',max:240)],
    _field(applies,'Aplica cuando (una condición por línea)',max:6000,maxLines:4,onChanged:() { setState(() { termsAcknowledged=false; previewed=false; }); }),_field(excludes,'No aplica cuando (una condición por línea)',max:6000,maxLines:4,onChanged:() { setState(() { termsAcknowledged=false; previewed=false; }); }),
    CheckboxListTile(contentPadding:EdgeInsets.zero,value:termsAcknowledged,onChanged:busy?null:(value) { setState(() { termsAcknowledged=value??false; previewed=false; }); },title:const Text('Confirmo que las condiciones aplicables y exclusiones son completas y claras para el cliente.'),controlAffinity:ListTileControlAffinity.leading),
    if(previewText!=null) Card(color:context.dlc.optimalContainer,child:Padding(padding:const EdgeInsets.all(12),child:Text(previewText!))),
    OutlinedButton.icon(onPressed:busy?null:_preview,icon:const Icon(CupertinoIcons.eye),label:const Text('Validar y previsualizar fechas')),
    FilledButton.icon(onPressed:busy?null:_save,icon:const Icon(CupertinoIcons.tray_arrow_down),label:Text(busy?'Guardando…':'Guardar borrador')),
  ]));

  Widget _field(TextEditingController controller,String label,{int max=500,int maxLines=1,TextInputType? keyboard,VoidCallback? onChanged}) => Padding(padding:const EdgeInsets.only(top:12),child:TextField(controller:controller,maxLength:max,minLines:maxLines==1?1:maxLines,maxLines:maxLines,keyboardType:keyboard,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder(),counterText:''),onChanged:(_){if(onChanged!=null){onChanged();}else{setState(()=>previewed=false);}}));
}

Map<String,dynamic> _map(dynamic value)=>value is Map?Map<String,dynamic>.from(value):const {};
List<String> _lines(dynamic value)=>value is List?value.map((x)=>x.toString()).toList():const [];
String _str(dynamic value)=>value?.toString()??'';
String _dateLabel(DateTime value)=>'${value.year.toString().padLeft(4,'0')}-${value.month.toString().padLeft(2,'0')}-${value.day.toString().padLeft(2,'0')}';
String _promotionCommandId() { final random = Random.secure(); final bytes = List<int>.generate(16, (_) => random.nextInt(256)); bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80; final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(); return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}'; }
String _headline(Map<String,dynamic> value)=>switch(_str(value['kind'])){'unit_discount'=>'USD ${_str(value['value'])} menos / ${_str(value['valueUnit'])}','percent_discount'=>'${_str(value['value'])}% descuento','cashback'=>'${_str(value['value'])}% cashback · tope USD ${_str(value['benefitCapUsd'])}','points_multiplier'=>'${_str(value['value'])}× puntos',_=>'Anuncio'};
