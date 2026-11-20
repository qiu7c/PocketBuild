"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

class Element {
    constructor(id) { this.id=id; this.children=[]; this.value=""; this.hidden=false; this.disabled=false; this.textContent=""; }
    replaceChildren(...items) { this.children=items; if (["project","job-history"].includes(this.id)) this.value=""; }
    append(item) { this.children.push(item); }
    add(option) { this.children.push(option); if (!this.value) this.value=option.value; }
    setAttribute(name,value) { this[name]=value; }
    click() { if (this.onclick) return this.onclick(); }
    focus() {this.focused=true;}
    setSelectionRange(start,end) {this.selectionStart=start;this.selectionEnd=end;}
}
const elements = new Map();
const element = id => {
    if (!elements.has(id)) elements.set(id,new Element(id));
    return elements.get(id);
};
const files = new Map([["Tweak.m","#import <Foundation/Foundation.h>"], ["MobileCompiler.json", JSON.stringify({
    productName:"Demo", sources:["Tweak.m"], customOption:"preserved", package:false, exportDylib:true
})]]);
const uploads = new Map();
const requests = [];
let sequence=0;
let failChunk=false;
let rejectPairing=false;
let job={state:"idle",artifacts:[]};
let snapshotChanged=false;
let downloadRoute="";
const projectRows = [{id:"p1",name:"Demo",productType:"tweak"},{id:"p2",name:"Demo",productType:"app"}];
const projectFiles = new Map([["p1",files],["p2",new Map()]]);
const past = {id:"build-123",state:"succeeded",artifacts:["Demo-unsigned.ipa"],log:"done",startedAt:12};
const context = {
    console, Blob, URL, TextEncoder, setTimeout: callback => callback(), setInterval: () => {},
    window:{addEventListener:()=>{}}, sessionStorage:{getItem:()=>null,setItem:()=>{},removeItem:()=>{}},
    document:{getElementById:element,createElement:tag=>new Element(tag)},
    Option:class { constructor(text,value) { this.text=text;this.value=value; } },
    confirm:()=>true,prompt:()=>"NewProject",
    getComputedStyle:()=>({lineHeight:"20"}),
    FileReader:class {
        readAsDataURL(blob) {
            blob.arrayBuffer().then(bytes => {
                this.result="data:application/octet-stream;base64,"+Buffer.from(bytes).toString("base64");
                this.onload();
            }).catch(error=>this.onerror(error));
        }
    },
    fetch:async (route,request) => {
        if (route.startsWith("/download")) {downloadRoute=route;return {ok:true,status:200,blob:async()=>new Blob(["artifact"])};}
        const body=JSON.parse(request.body);
        requests.push(body);
        if (rejectPairing) return {ok:false,status:401,json:async()=>({error:"连接码无效"})};
        let status=200, result={};
        switch(body.action) {
            case "projects": result={projects:projectRows}; break;
            case "files":
                result={files:[...projectFiles.get(body.project).keys()],buildDefaults:{sdkVersion:"26.0",deploymentTarget:"17.0",
                    exportDylib:false,package:true,packageSchemes:["roothide"]},
                    summary:{sdk:"26.0",cpu:"arm64",outputs:["dylib"],issue:{kind:"components",message:"缺少 iOS 26.0 SDK"}}};
                break;
            case "read": result={content:projectFiles.get(body.project).get(body.path)}; break;
            case "tools": result={compilerBundled:true}; break;
            case "create":
                if (body.empty) {
                    projectRows.push({id:"p3",name:body.name,productType:body.productType});
                    projectFiles.set("p3",new Map());
                    result={id:"p3"};
                } else result={id:"p1"};
                break;
            case "rename_project":
                projectRows.find(row=>row.id===body.project).name=body.name;
                result={id:body.project,name:body.name};
                break;
            case "history": result={builds:body.project==="p1" ? [past] : []}; break;
            case "job": result=body.job_id===past.id ? past : body.project==="p2" ? {state:"idle"} : job; break;
            case "diagnostic_source":
                assert.equal(body.job_id, job.id);
                result={path:"Tweak.m", text:snapshotChanged ? "开头\r\n中error" : files.get("Tweak.m"),
                    snapshot:snapshotChanged,currentAvailable:true,line:2,column:snapshotChanged ? 4 : 6};
                if (snapshotChanged) result.text=result.text.replaceAll("\r\n","\n");
                break;
            case "upload_begin":
                result={upload:String(++sequence)};
                uploads.set(result.upload,{project:body.project,path:body.path,bytes:Buffer.alloc(0)});
                break;
            case "upload_chunk": {
                if(failChunk && body.offset>0) {status=500;result={error:"disk full fixture"};break;}
                const upload=uploads.get(body.upload);
                assert.equal(body.offset,upload.bytes.length);
                upload.bytes=Buffer.concat([upload.bytes,Buffer.from(body.data,"base64")]);
                result={offset:upload.bytes.length};
                break;
            }
            case "upload_finish": {
                const upload=uploads.get(body.upload);
                assert.equal(body.size,upload.bytes.length);
                projectFiles.get(upload.project).set(upload.path,upload.bytes.toString("utf8"));
                uploads.delete(body.upload);
                result={saved:true};
                break;
            }
            case "upload_abort": uploads.delete(body.upload);result={aborted:true};break;
            case "build": job={id:"build-active",state:"running",stage:"clang",artifacts:[],log:"compiling"};result={id:job.id,state:"running"};break;
            case "cancel": job={state:"cancelled",artifacts:[],log:"cancelled"};result={state:"cancelling"};break;
            default: throw new Error("Unexpected action "+body.action);
        }
        return {ok:status===200,status,json:async()=>result};
    },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname,"../Resources/BuildWeb/app.js"),"utf8"),context);
async function main() {
    rejectPairing=true;
    element("code").value="wrong-code";
    await element("connect-form").onsubmit();
    assert.equal(element("pairing-message").textContent,"连接码无效");
    rejectPairing=false;
    element("code").value="pairing-code";
    await element("connect-form").onsubmit();
    assert.equal(element("workspace").hidden,false);
    assert.equal(element("pairing-message").textContent,"");
    assert.equal(element("project").value,"p1");
    assert.notEqual(element("project").children[0].text,element("project").children[1].text);
    assert.equal(element("option-sdk").value,"26.0");
    assert.equal(element("option-minimum").value,"17.0");
    assert.equal(element("option-package").checked,false);
    assert.equal(element("option-dylib").checked,true);
    assert.equal(element("option-roothide").checked,true);
    assert.equal(element("project-readiness").textContent,"缺少 iOS 26.0 SDK");
    element("product-type").value="app";
    await element("create").onclick();
    assert.equal(requests.find(item=>item.action==="create").productType,"app");
    await element("files").children[0].children[0].onclick();
    element("content").value="中文源码\nvoid test(void) {}";
    element("content").oninput();
    assert.equal(element("line-numbers").textContent,"1\n2");
    assert.equal(element("unsaved").hidden,false);
    await element("save").onclick();
    assert.equal(element("unsaved").hidden,true);
    assert.equal(files.get("Tweak.m"),element("content").value);
    assert.equal(uploads.size,0);
    element("option-product").value="tweak";
    element("option-dylib").checked=true;
    element("option-package").checked=true;
    for(const scheme of ["rootless","rootful","roothide"]) element("option-"+scheme).checked=true;
    element("option-cpu").value="arm64e";
    await element("options-form").onsubmit();
    const config=JSON.parse(files.get("MobileCompiler.json"));
    assert.deepEqual(config.packageSchemes,["rootless","rootful","roothide"]);
    assert.equal(config.exportDylib,true);
    assert.equal(config.package,true);
    assert.equal(config.cpuArchitecture,"arm64e");
    assert.deepEqual(config.sources,["Tweak.m"]);
    assert.equal(config.customOption,"preserved");
    element("option-dylib").checked=false;
    element("option-package").checked=false;
    await element("options-form").onsubmit();
    assert.match(element("message").textContent,/请选择独立 dylib 或 DEB/);
    assert.equal(files.get("MobileCompiler.json"),JSON.stringify(config,null,2)+"\n");
    const blob=new Blob(["x".repeat(1200000)]);
    blob.name="Large.mm";
    blob.webkitRelativePath="Demo/Large.mm";
    element("folder-input").files=[blob];
    const before=requests.length;
    await element("folder-input").onchange();
    const chunks=requests.slice(before).filter(item=>item.action==="upload_chunk");
    assert.equal(chunks.length,3);
    assert.deepEqual(chunks.map(item=>item.offset),[0,524288,1048576]);
    assert.equal(files.get("Large.mm").length,1200000);
    assert.equal(element("project").disabled,false);

    failChunk=true;
    element("folder-input").files=[blob];
    await element("folder-input").onchange();
    assert.equal(uploads.size,0);
    assert.equal(files.get("Large.mm").length,1200000);
    assert.equal(element("message").textContent,"disk full fixture");
    failChunk=false;
    await element("build").onclick();
    assert.equal(element("build").disabled,true);
    assert.equal(element("cancel").disabled,false);
    assert.match(element("job-state").textContent,/clang/);
    await element("cancel").onclick();
    assert.equal(requests.find(item=>item.action==="cancel").job_id,"build-active");
    await vm.runInContext("poll()",context);
    assert.equal(element("job-state").textContent,"已取消");
    job={id:"build-123",state:"succeeded",artifacts:["Demo-unsigned.ipa","build.log","report.json"],log:"done"};
    await vm.runInContext("poll()",context);
    assert.equal(element("artifacts").children.length,1);
    assert.equal(element("panel-artifacts").hidden,false);
    assert.equal(element("log-downloads").hidden,false);
    await element("artifacts").children[0].onclick();
    assert.equal(downloadRoute,"/download?file=Demo-unsigned.ipa&job=build-123");
    job={id:"missing-sdk",state:"failed",issue:{kind:"components",message:"缺少 iOS 16.4 SDK"},artifacts:[]};
    await vm.runInContext("poll()",context);
    assert.match(element("issue-message").textContent,/缺少 iOS 16.4 SDK/);
    assert.equal(element("panel-problems").hidden,false);
    assert.equal(element("jump-to-error").hidden,true);

    job={id:"compiler-error",state:"failed",issue:{kind:"compiler",file:"Tweak.m",line:2,column:6,message:"broken"},artifacts:[]};
    await vm.runInContext("poll()",context);
    assert.match(element("issue-message").textContent,/Tweak.m:2:6/);
    await element("jump-to-error").onclick();
    assert.equal(element("filename").textContent,"Tweak.m");
    assert.equal(element("content").selectionStart,10);
    assert.equal(element("content").readOnly,false);
    snapshotChanged=true;
    await element("jump-to-error").onclick();
    assert.equal(element("content").readOnly,true);
    assert.equal(element("content").selectionStart,4);
    assert.equal(element("content").selectionEnd,5);
    assert.equal(element("source-context").hidden,false);
    await element("edit-current").onclick();
    assert.equal(element("content").value,files.get("Tweak.m"));
    assert.equal(element("content").readOnly,false);
    assert.equal(element("source-context").hidden,true);

    await element("load-history").onclick();
    element("job-history").value="build-123";
    await element("job-history").onchange();
    assert.equal(requests.at(-1).job_id,"build-123");
    assert.equal(element("job-state").textContent,"编译成功");
    element("project").value="p2";
    await element("project").onchange();
    await vm.runInContext("poll()",context);
    assert.equal(requests.at(-1).project,"p2");
    assert.equal(element("job-state").textContent,"无构建任务");
    await element("rename-project").onclick();
    assert.equal(projectRows[1].name,"NewProject");

    element("import-input").files=[blob];
    await element("import-input").onchange();
    assert.equal(element("project").value,"p3");
    assert.equal(projectFiles.get("p3").get("Large.mm").length,1200000);
    assert.equal(projectFiles.get("p2").size,0);
    console.log("PASS: browser upload, build/cancel, per-project history, component hint, source jump and new-project import.");
}
main().catch(error=>{console.error(error);process.exitCode=1;});
