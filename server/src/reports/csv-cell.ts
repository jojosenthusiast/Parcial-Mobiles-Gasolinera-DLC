export function csvCell(value:unknown):string {
 let text=value===null||value===undefined?'':typeof value==='object'?JSON.stringify(value):String(value);
 if(/^[\s\uFEFF]*[=+\-@\t\r]/u.test(text))text="'"+text;
 return '"'+text.replaceAll('"','""')+'"';
}
