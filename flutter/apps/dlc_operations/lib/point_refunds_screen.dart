import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';
import 'format.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

class PointRefundsScreen extends StatefulWidget {
 const PointRefundsScreen({required this.api,required this.branchId,required this.permissions,super.key});
 final EmployeeSession api;final String branchId;final Set<String> permissions;
 @override State<PointRefundsScreen> createState()=>_PointRefundsScreenState();
}
class _PointRefundsScreenState extends State<PointRefundsScreen> {
 final search=TextEditingController();List<Map<String,dynamic>> sales=const[];Map<String,dynamic>? detail;String? saleId,error;bool busy=false;
 @override void initState(){super.initState();loadSales();}
 @override void dispose(){search.dispose();super.dispose();}
 Future<void> loadSales()async{setState(()=>busy=true);try{final rows=await widget.api.refundSales(widget.branchId,search.text.trim());if(mounted)setState(()=>sales=rows);}on DlcApiException catch(e){if(mounted)setState(()=>error=e.message);}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> load(String id)async{setState((){busy=true;saleId=id;detail=null;error=null;});try{final data=await widget.api.pointRefunds(widget.branchId,id);if(mounted)setState(()=>detail=data);}on DlcApiException catch(e){if(mounted)setState(()=>error=e.message);}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> command(Map<String,dynamic> row,bool decision)async{
  final reason=TextEditingController(),points=TextEditingController();String outcome='approved';
  final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,update)=>AlertDialog(title:Text(decision?'Decidir devolución de puntos':'Solicitar devolución de puntos'),content:Column(mainAxisSize:MainAxisSize.min,children:[
   Text(decision?'${row['points']} puntos. Requiere otra persona distinta al solicitante.':'Devuelve puntos a la misma cuenta, sin salida de efectivo.'),
   if(decision)DropdownButtonFormField<String>(initialValue:outcome,items:const[DropdownMenuItem(value:'approved',child:Text('Aprobar')),DropdownMenuItem(value:'rejected',child:Text('Rechazar'))],onChanged:(v)=>update(()=>outcome=v??outcome))
   else TextField(controller:points,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Cantidad entera de puntos')),
   TextField(controller:reason,maxLines:3,decoration:const InputDecoration(labelText:'Motivo de devolución / decisión')),
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Volver')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Confirmar'))])));
  final count=int.tryParse(points.text.trim());final note=reason.text.trim();reason.dispose();points.dispose();if(ok!=true||!mounted)return;
  if(note.length<8||(!decision&&(count==null||count<1))){setState(()=>error='Indica motivo de al menos 8 caracteres y puntos enteros positivos.');return;}
  setState(()=>busy=true);
  try{await widget.api.pointRefundCommand(widget.branchId,saleId!,decision,{'reason':note,if(decision)...{'requestId':row['id'],'decision':outcome}else...{'paymentId':row['id'],'points':count}});await load(saleId!);}
  on DlcApiException catch(e){if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>busy=false);}
 }
 List<Map<String,dynamic>> rows(String key)=>(detail?[key] as List<dynamic>? ?? const[]).whereType<Map<String,dynamic>>().toList();
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Devoluciones de puntos')),body:ListView(padding:const EdgeInsets.all(16),children:[
  TextField(controller:search,decoration:InputDecoration(labelText:'Buscar venta por folio o descripción',suffixIcon:IconButton(onPressed:busy?null:loadSales,icon:const Icon(CupertinoIcons.search))),onSubmitted:(_)=>loadSales()),
  if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
  if(saleId==null)...sales.map((s)=>ListTile(title:Text('${s['code']??s['description']??s['id']}'),subtitle:Text('${moneyRaw(s['totalUsd']??s['total_usd'])}'),trailing:const Icon(CupertinoIcons.chevron_right),onTap:busy?null:()=>load('${s['id']}')))
  else ...[TextButton(onPressed:busy?null:()=>setState((){saleId=null;detail=null;}),child:const Text('Volver a ventas')),Text('Venta $saleId'),
   ...rows('payments').map((p)=>Card(child:ListTile(title:Text('${p['points']} puntos · ${moneyRaw(p['amountUsd'])}'),subtitle:Text('Devueltos: ${p['returnedPoints']} puntos'),trailing:widget.permissions.contains('sale.refund.request')?TextButton(onPressed:busy?null:()=>command(p,false),child:const Text('Solicitar')):null))),
   ...rows('requests').map((r)=>Card(child:ListTile(title:Text('${r['points']} puntos · ${r['decision']??'Pendiente'}'),subtitle:Text('${r['reason']}'),trailing:r['decision']==null&&widget.permissions.contains('payment.refund')?TextButton(onPressed:busy?null:()=>command(r,true),child:const Text('Decidir')):null))),
   if(detail!=null&&rows('payments').isEmpty)const Text('Esta venta no tiene pagos con puntos.'),
  ],
 ]));
}
