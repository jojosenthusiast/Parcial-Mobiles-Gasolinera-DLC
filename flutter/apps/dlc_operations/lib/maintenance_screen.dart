import 'package:dlc_api/dlc_api.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({required this.api, required this.branchId, required this.permissions, super.key});
  final EmployeeSession api;
  final String branchId;
  final Set<String> permissions;
  @override State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  List<Map<String,dynamic>> _assets=const[],_orders=const[];
  bool _loading=true;
  String? _error;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    setState(()=>_loading=true);_error=null;
    try{final values=await Future.wait<dynamic>([widget.api.maintenanceAssets(widget.branchId),widget.api.maintenanceOrders(widget.branchId)]);_assets=values[0] as List<Map<String,dynamic>>;_orders=values[1] as List<Map<String,dynamic>>;}
    on DlcApiException catch(e){_error=e.message;}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _create() async {
    if(_assets.isEmpty){_message('Registra el equipo en infraestructura antes de abrir una orden.');return;}
    String assetId=_str(_assets.first['id']),kind='corrective';final description=TextEditingController();
    final data=await showDialog<({String asset,String kind,String description})>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setState)=>AlertDialog(
      title:const Text('Nueva orden de mantenimiento'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(initialValue:assetId,decoration:const InputDecoration(labelText:'Equipo'),items:_assets.map((a)=>DropdownMenuItem(value:_str(a['id']),child:Text('${_str(a['assetType'])} · ${_str(a['assetCode']??a['assetId'])}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>assetId=v??assetId)),
        const SizedBox(height:8),DropdownButtonFormField<String>(initialValue:kind,decoration:const InputDecoration(labelText:'Tipo'),items:const[DropdownMenuItem(value:'corrective',child:Text('Correctivo')),DropdownMenuItem(value:'preventive',child:Text('Preventivo')),DropdownMenuItem(value:'inspection',child:Text('Inspección'))],onChanged:(v)=>setState(()=>kind=v??kind)),
        const SizedBox(height:8),TextField(controller:description,minLines:3,maxLines:5,maxLength:1000,decoration:const InputDecoration(labelText:'Descripción')),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Volver')),FilledButton(onPressed:()=>Navigator.pop(context,(asset:assetId,kind:kind,description:description.text.trim())),child:const Text('Crear'))],
    )));
    description.dispose();if(data==null||data.description.length<8)return;
    await _mutate(()=>widget.api.createMaintenanceOrder(widget.branchId,assetProfileId:data.asset,kind:data.kind,dueKey:DateTime.now().toUtc().toIso8601String(),description:data.description));
  }
  Future<void> _start(Map<String,dynamic> row)=>_advance(row,'in_progress');
  Future<void> _complete(Map<String,dynamic> row) async {
    final values=await _taskDialog(context);if(values==null)return;
    await _mutate(()async{await widget.api.addMaintenanceTask(widget.branchId,_str(row['id']),description:values.$1,result:values.$2);await widget.api.advanceMaintenanceOrder(widget.branchId,_str(row['id']),_int(row['version']),'completed',diagnosis:values.$2);});
  }
  Future<void> _advance(Map<String,dynamic> row,String status)=>_mutate(()=>widget.api.advanceMaintenanceOrder(widget.branchId,_str(row['id']),_int(row['version']),status));
  Future<void> _mutate(Future<dynamic> Function() action)async{setState(()=>_loading=true);_error=null;try{await action();await _load();}on DlcApiException catch(e){if(mounted)setState(()=>_error=e.message);await _load();}}
  void _message(String v){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(v)));}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Mantenimiento'),actions:[IconButton(onPressed:_loading?null:_load,tooltip:'Actualizar',icon:const Icon(Icons.refresh))]),
    floatingActionButton:widget.permissions.contains('maintenance.plan')?FloatingActionButton.extended(onPressed:_loading?null:_create,icon:const Icon(Icons.add),label:const Text('Nueva orden')):null,
    body:_loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
      if(_error!=null)Card(color:context.dlc.criticalContainer,child:ListTile(leading:const Icon(Icons.error_outline),title:Text(_error!))),
      if(_orders.isEmpty)const Card(child:ListTile(leading:Icon(Icons.build_outlined),title:Text('No hay órdenes de mantenimiento abiertas.'))),
      ..._orders.map((row){final status=_str(row['status']);final asset=_assets.where((a)=>_str(a['id'])==_str(row['assetProfileId'])).firstOrNull;final assetLabel=asset==null?_str(row['assetType']):'${_str(asset['assetType'])} · ${_str(asset['assetCode']??asset['assetId'])}';
        final canWork=widget.permissions.contains('maintenance.work');final actions=<Widget>[];
        if(status=='planned'&&canWork)actions.add(TextButton(onPressed:()=>_start(row),child:const Text('Iniciar')));
        if(status=='in_progress'&&canWork)actions.add(TextButton(onPressed:()=>_complete(row),child:const Text('Registrar tarea y completar')));
        if(status=='completed'&&widget.permissions.contains('maintenance.verify'))actions.add(TextButton(onPressed:()=>_advance(row,'verified'),child:const Text('Verificar')));
        return Card(margin:const EdgeInsets.only(bottom:8),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(assetLabel,style:const TextStyle(fontWeight:FontWeight.w800))),Chip(label:Text(status))]),
          Text('${_str(row['kind'])} · ${_str(row['description'])}'),
          if(actions.isNotEmpty)Wrap(alignment:WrapAlignment.end,children:actions),
        ])));}),
    ])),
  );
}
Future<(String,String)?> _taskDialog(BuildContext context)async{final task=TextEditingController(),result=TextEditingController();final values=await showDialog<(String,String)>(context:context,builder:(context)=>AlertDialog(title:const Text('Trabajo realizado'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:task,decoration:const InputDecoration(labelText:'Tarea (mín. 5 caracteres)')),TextField(controller:result,minLines:2,maxLines:4,decoration:const InputDecoration(labelText:'Resultado/diagnóstico'))]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Volver')),FilledButton(onPressed:()=>Navigator.pop(context,(task.text.trim(),result.text.trim())),child:const Text('Guardar y completar'))]));task.dispose();result.dispose();return values;}
String _str(dynamic v)=>v?.toString()??'';
int _int(dynamic v)=>int.tryParse('$v')??1;
