import 'package:dlc_api/dlc_api.dart';
import 'haptics.dart';
import 'live_form.dart';
import 'validators.dart';
import 'package:flutter/material.dart';

class ContaminationScreen extends StatefulWidget {
 const ContaminationScreen({required this.api,required this.branchId,required this.order,required this.tanks,required this.permissions,super.key});
 final Set<String> permissions;
 final EmployeeSession api; final String branchId;
 final Map<String,dynamic> order; final List<Map<String,dynamic>> tanks;
 @override State<ContaminationScreen> createState()=>_ContaminationScreenState();
}
class _ContaminationScreenState extends State<ContaminationScreen> {
 final quantity=TextEditingController(),document=TextEditingController(),description=TextEditingController();
 final form=GlobalKey<FormState>(); String? tankId,lineId,error; Map<String,dynamic>? preview,result; bool busy=false;
 List<Map<String,dynamic>> get lines => (widget.order['lines'] as List<dynamic>? ?? const []).whereType<Map<String,dynamic>>().toList();
 List<Map<String,dynamic>> history=const []; List<Map<String,dynamic>> products=const [];
 String volumeBoth(dynamic value){final liters=double.tryParse('${value??''}');if(liters==null)return 'Desconocido';return '${liters.toStringAsFixed(3)} L · ${(liters/3.785411784).toStringAsFixed(2)} gal US';}
 @override void initState(){super.initState();loadHistory();loadProducts();}
 Future<void> loadProducts()async{try{final data=await widget.api.fuelProducts(branchId:widget.branchId);if(mounted)setState(()=>products=data);}on DlcApiException catch(e){if(mounted)setState(()=>error=e.message);}}
 String productName(dynamic id){for(final product in products){if(product['id']=='$id')return '${product['displayName']??product['name']??id}';}return '$id';}
 Future<void> loadHistory()async{try{final data=await widget.api.contaminatedDeliveries(widget.branchId,'${widget.order['id']}');if(mounted)setState(()=>history=data);}on DlcApiException catch(e){if(mounted)setState(()=>error=e.message);}}
 Future<void> resolve(Map<String,dynamic> row,bool disposal)async{
  final note=TextEditingController(),measured=TextEditingController(),evidence=TextEditingController();
  String? noteError(String? v)=>minLengthText(v,8,field:disposal?'El detalle':'El motivo');
  String? measuredError(String? v)=>positiveNumber(v,field:'El volumen retirado',maxDecimals:3);
  String? evidenceError(String? v)=>minLengthText(v,3,field:'El documento');
  final confirmed=await showDialog<bool>(context:context,builder:(c)=>ValidatedFormDialog(title:disposal?'Verificar retiro físico':'Aprobar pérdida del producto entrante',submitLabel:'Confirmar',cancelLabel:'Volver',onCancel:()=>Navigator.pop(c,false),onSubmit:()=>Navigator.pop(c,true),isValid:()=>allValid([noteError(note.text),if(disposal)measuredError(measured.text),if(disposal)evidenceError(evidence.text)]),contentBuilder:(c,changed)=>Column(mainAxisSize:MainAxisSize.min,children:[
   Text(disposal?'Las dos pérdidas deben estar aprobadas. Se conserva evidencia de retiro; mantenimiento verificará limpieza antes de liberar.':'USD ${row['incoming_cost_usd']}. La pérdida previa del tanque se aprueba en Incidencias.'),
   if(disposal)LiveTextField(controller:measured,keyboardType:LiveTextField.decimal(),label:'Volumen retirado medido (L)',helper:'La API registra litros; 1 gal US = 3.785411784 L.',validator:measuredError,onChanged:changed),
   if(disposal)LiveTextField(controller:evidence,label:'Documento de disposición',validator:evidenceError,onChanged:changed),
   LiveTextField(controller:note,maxLines:3,label:disposal?'Detalle y diferencias de medición':'Motivo de aprobación',validator:noteError,onChanged:changed),
  ])));
  final body=<String,dynamic>{if(disposal)...{'measuredLiters':measured.text.trim(),'evidenceReference':evidence.text.trim(),'note':note.text.trim()}else 'reason':note.text.trim()};
  note.dispose();measured.dispose();evidence.dispose();if(confirmed!=true||!mounted)return;
  setState(()=>busy=true);
  try{await widget.api.resolveContamination(widget.branchId,'${row['id']}',disposal?'disposal-verification':'incoming-loss-approval',body);Haptics.success();await loadHistory();}
  on DlcApiException catch(e){Haptics.error();if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override void dispose(){quantity.dispose();document.dispose();description.dispose();super.dispose();}
 Future<void> selectTank(String? value)async{
  setState((){tankId=value;preview=null;error=null;busy=true;});
  try{final data=await widget.api.contaminationPreview(widget.branchId,value!);if(mounted&&tankId==value)setState(()=>preview=data);}
  on DlcApiException catch(e){if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> submit()async{
  if(!(form.currentState?.validate()??false)){Haptics.error();return;}
  if(preview==null||lineId==null||tankId==null)return;
  final line=lines.firstWhere((l)=>l['id']==lineId);
  final confirmed=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Bloquear tanque y registrar descarga'),content:Text('Se registrará SOLO la cantidad realmente descargada: ${quantity.text} ${line['unit']}. El tanque quedará bloqueado. El resto del pedido no se considera perdido.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Revisar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Confirmar incidencia'))]));
  if(confirmed!=true||!mounted)return;
  setState((){busy=true;error=null;});
  try{final data=await widget.api.reportContamination(widget.branchId,'${widget.order['id']}',{
   'purchaseOrderLineId':lineId,'tankId':tankId,'expectedBalanceVersion':int.parse('${preview!['balanceVersion']}'),
   'actualQuantity':quantity.text.trim(),'unit':line['unit'],'documentReference':document.text.trim(),'description':description.text.trim()});
   Haptics.critical();
   if(mounted)setState(()=>result=data);
  }on DlcApiException catch(e){Haptics.error();if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Descarga en tanque equivocado')),body:Form(key:form,autovalidateMode:AutovalidateMode.onUserInteraction,child:ListView(padding:const EdgeInsets.all(16),children:[
  const Card(child:Padding(padding:EdgeInsets.all(12),child:Text('Detén la descarga y aplica el protocolo de seguridad de la estación. Este registro bloquea el tanque; no certifica limpieza ni retiro.'))),
  if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
  if(result==null)...[
   DropdownButtonFormField<String>(initialValue:lineId,decoration:const InputDecoration(labelText:'Combustible comprado / línea'),items:lines.map((l)=>DropdownMenuItem(value:'${l['id']}',child:Text('${productName(l['fuelProductId'])} · ${l['quantityOrdered']} ${l['unit']}'))).toList(),onChanged:busy?null:(v)=>setState(()=>lineId=v),validator:(v)=>v==null?'Selecciona una línea':null),
   DropdownButtonFormField<String>(initialValue:tankId,decoration:const InputDecoration(labelText:'Tanque realmente afectado'),items:widget.tanks.map((t)=>DropdownMenuItem(value:'${t['id']}',child:Text('${t['code']} · ${t['name']??t['fuelProductId']}'))).toList(),onChanged:busy?null:selectTank,validator:(v)=>v==null?'Selecciona el tanque':null),
   if(preview!=null)Card(child:Padding(padding:const EdgeInsets.all(12),child:Text('Contenido previo: ${volumeBoth(preview!['priorQuantityL'])}\nCosto histórico: ${preview!['costQuality']=='known'?'USD ${preview!['priorCostUsd']}':'Desconocido: requiere conciliación'}\nVersión del saldo: ${preview!['balanceVersion']}'))),
   TextFormField(controller:quantity,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Cantidad REAL descargada (unidad de compra)'),validator:(v)=>RegExp(r'^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$').hasMatch(v?.trim()??'')?null:'Indica una cantidad positiva, usando punto decimal'),
   TextFormField(controller:document,decoration:const InputDecoration(labelText:'Documento de entrega'),maxLength:120,validator:(v)=>(v?.trim().length??0)<3?'Documento requerido':null),
   TextFormField(controller:description,decoration:const InputDecoration(labelText:'Qué ocurrió y cómo se detectó'),maxLines:4,maxLength:2000,validator:(v)=>(v?.trim().length??0)<12?'Explica la incidencia':null),
   FilledButton(onPressed:busy||preview==null?null:submit,child:Text(busy?'Registrando…':'Registrar y bloquear tanque')),
  ] else Card(child:Padding(padding:const EdgeInsets.all(16),child:Text('Incidencia: ${result!['incident_id']}\nContenido previo afectado: ${volumeBoth(result!['prior_quantity_l'])}\nProducto descargado afectado: ${volumeBoth(result!['incoming_quantity_l'])}\nCosto previo: ${result!['prior_cost_usd']??'Desconocido'} USD\nCosto entrante: ${result!['incoming_cost_usd']} USD\nPedido restante: ${result!['remaining_order_quantity']} ${result!['unit']}\nTanque bloqueado. Liquidación y disposición deben aprobarse por separado.'))),
  ...history.map((row)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Text('Incidencia ${row['incident_id']}'),Text('Previo: ${volumeBoth(row['prior_quantity_l'])} · Descargado: ${volumeBoth(row['incoming_quantity_l'])}'),
   Text('Costos: ${row['prior_cost_usd']??'desconocido'} + ${row['incoming_cost_usd']} USD'),Text('Restante: ${row['remaining_order_quantity']} ${row['unit']}'),
   if(widget.permissions.contains('loss.approve')&&row['incoming_loss_approval_id']==null)TextButton(onPressed:busy?null:()=>resolve(row,false),child:const Text('Aprobar pérdida entrante')),
   if(widget.permissions.contains('incident.resolve')&&row['disposal_id']==null)TextButton(onPressed:busy?null:()=>resolve(row,true),child:const Text('Verificar retiro')),
   if(row['disposal_id']!=null)Text('Retiro verificado: ${volumeBoth(row['disposed_l'])}. Requiere mantenimiento e inspección para liberar.'),
  ])))),
 ])));
}
