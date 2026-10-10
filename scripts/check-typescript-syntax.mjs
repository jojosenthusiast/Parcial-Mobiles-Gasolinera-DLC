// Syntax-only fallback when the full Nest/TypeScript dependency installation is unavailable.
// This does not resolve imports, check types or execute Nest decorators.
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { Script } from 'node:vm';
function withoutDecorators(source){
 const ranges=[];const expression=/@[A-Za-z][\w.]*/g;let match;
 while((match=expression.exec(source))){
  let end=expression.lastIndex;while(/\s/.test(source[end]??''))end++;
  if(source[end]==='('){
   let depth=0,quote=null,escaped=false;
   do{
    const c=source[end++];
    if(quote){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c===quote)quote=null;}
    else if(c==='"'||c==="'"||c==='`')quote=c;
    else if(c==='(')depth++;else if(c===')')depth--;
   }while(end<source.length&&(depth>0||quote));
   if(depth!==0)throw Error('Unbalanced decorator');
  }
  ranges.push([match.index,end]);expression.lastIndex=end;
 }
 for(const [start,end] of ranges.reverse())source=source.slice(0,start)+source.slice(end);
 return source;
}
for(const path of process.argv.slice(2)){
 const source=await readFile(path,'utf8');
 let code=stripTypeScriptTypes(withoutDecorators(source),{mode:'transform'});
 code=code.replace(/^\s*import\s+[\s\S]*?\s+from\s+['"][^'"]+['"]\s*;?\s*$/gm,'')
  .replace(/^\s*import\s+['"][^'"]+['"]\s*;?\s*$/gm,'')
  .replace(/^\s*export\s*\{[^}]*\}\s*;?\s*$/gm,'')
  .replace(/\bexport\s+(?=(?:declare\s+)?(?:async\s+)?(?:class|function|const|let|var|type|interface|enum|abstract\s+class)\b)/g,'');
 new Script(`(async()=>{\n${code}\n})`,{filename:path});
 process.stdout.write(`PASS syntax-only: ${path}\n`);
}
