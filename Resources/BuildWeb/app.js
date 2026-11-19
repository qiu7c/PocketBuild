"use strict";
const element = id => document.getElementById(id);
let token = sessionStorage.getItem("buildCode") || "";
let project = "";
let filename = "";
let dirty = false;
let running = false;
let polling = false;
let uploading = false;
let generation = 0;
let currentJob = "";

function message(text) { element("message").textContent = text; }
async function api(action, data = {}) {
    const response = await fetch("/api/v1/workspace", {
        method: "POST", headers: {"Content-Type":"application/json", Authorization:"Bearer " + token},
        body: JSON.stringify({action, ...data})
    });
    let result;
    try { result = await response.json(); }
    catch { throw new Error("请求失败，HTTP " + response.status); }
    if (!response.ok) throw new Error(typeof result.error === "string" ? result.error : "HTTP " + response.status);
    return result;
}
function handle(action) {
    return async event => {
        if (event) event.preventDefault();
        try { await action(); }
        catch (error) { message(error.message); }
    };
}
async function save() {
    if (!filename) return;
    await uploadBlob(project, filename, new Blob([element("content").value], {type:"text/plain;charset=utf-8"}));
    dirty = false;
    message("已保存 " + filename);
}
async function leaveFile() {
    if (!dirty) return;
    if (!confirm("当前文件有修改，保存后继续？")) throw new Error("操作已取消，修改仍在编辑器中");
    await save();
}
async function listFiles() {
    const result = await api("files", {project});
    element("files").replaceChildren();
    for (const path of result.files) {
        const item = document.createElement("li");
        const button = document.createElement("button");
        button.textContent = path;
        button.setAttribute("aria-current", String(path === filename));
        button.onclick = handle(async () => {
            await leaveFile();
            const file = await api("read", {project, path});
            filename = path;
            element("filename").textContent = path;
            element("content").value = file.content;
            element("content").disabled = false;
            element("save").disabled = false;
            await listFiles();
        });
        item.append(button);
        element("files").append(item);
    }
    element("options-fields").disabled = true;
    let config = {};
    if (result.files.includes("MobileCompiler.json")) {
        const manifest = await api("read", {project, path:"MobileCompiler.json"});
        try { config = JSON.parse(manifest.content); }
        catch { message("MobileCompiler.json 格式有误，请在编辑器修正后重新选择项目"); return; }
        if (!config || Array.isArray(config) || typeof config !== "object") {
            message("MobileCompiler.json 应为 JSON 对象"); return;
        }
    }
    element("option-product").value = config.productType || "tweak";
    element("tweak-options").hidden = config.productType === "app";
    element("option-dylib").checked = config.exportDylib !== false;
    element("option-package").checked = result.files.includes("MobileCompiler.json") && config.package !== false;
    const schemes = Array.isArray(config.packageSchemes) ? config.packageSchemes : [config.packageScheme || "rootless"];
    for (const scheme of ["rootless", "rootful", "roothide"]) element("option-" + scheme).checked = schemes.includes(scheme);
    element("option-cpu").value = config.cpuArchitecture || "arm64";
    element("option-sdk").value = config.sdkVersion || "16.4";
    element("option-minimum").value = config.deploymentTarget || "15.0";
    element("options-fields").disabled = false;
}
async function listProjects(selected = project) {
    const result = await api("projects");
    const select = element("project");
    select.replaceChildren();
    for (const item of result.projects) select.add(new Option(item.name, item.id));
    if (result.projects.some(item => item.id === selected)) select.value = selected;
    project = select.value;
    filename = "";
    dirty = false;
    element("filename").textContent = "选择文件";
    element("content").value = "";
    element("content").disabled = true;
    element("save").disabled = true;
    if (project) await listFiles(); else {element("files").replaceChildren();element("options-fields").disabled=true;}
}
async function download(file, jobID) {
    const response = await fetch("/download?file=" + encodeURIComponent(file) + "&job=" + encodeURIComponent(jobID), {headers:{Authorization:"Bearer " + token}});
    if (!response.ok) throw new Error("下载失败，HTTP " + response.status);
    const url = URL.createObjectURL(await response.blob());
    const link = document.createElement("a");
    link.href = url;
    link.download = file;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
}
async function poll() {
    if (!token || polling) return;
    const current = generation;
    polling = true;
    try {
        const job = await api("job");
        if (current !== generation) return;
        currentJob = job.id || "";
        running = job.state === "running";
        element("build").disabled = running || uploading;
        element("cancel").disabled = !running;
        const states = {idle:"无构建任务", running:"正在编译", succeeded:"编译成功", failed:"编译失败", cancelled:"已取消"};
        element("job-state").textContent = (states[job.state] || job.state) +
            (running && job.stage ? " · " + job.stage : "");
        element("log").textContent = job.log || "";
        element("artifacts").replaceChildren();
        for (const file of job.artifacts || []) {
            const button = document.createElement("button");
            button.textContent = "下载 " + file;
            button.onclick = handle(() => download(file, job.id));
            element("artifacts").append(button);
        }
    } catch (error) { if (current === generation) message(error.message); }
    finally { polling = false; }
}
function fileData(file) {
    return new Promise((resolve,reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result.split(",")[1]);
        reader.onerror = () => reject(new Error("读取文件失败"));
        reader.readAsDataURL(file);
    });
}
async function uploadBlob(targetProject, path, file) {
    const task = await api("upload_begin", {project:targetProject, path});
    try {
        const chunkSize = 512 * 1024;
        for (let offset = 0; offset < file.size; offset += chunkSize) {
            const data = await fileData(file.slice(offset, offset + chunkSize));
            await api("upload_chunk", {upload:task.upload, offset, data});
        }
        await api("upload_finish", {upload:task.upload, size:file.size});
    } catch (error) {
        await api("upload_abort", {upload:task.upload}).catch(() => {});
        throw error;
    }
}
async function upload(files, directory) {
    if (!project) throw new Error("请先新建项目");
    await leaveFile();
    const targetProject = project;
    uploading = true;
    element("build").disabled = true;
    element("project").disabled = true;
    element("upload").disabled = true;
    element("folder").disabled = true;
    element("create").disabled = true;
    try {
        for (const file of files) {
            const parts = file.webkitRelativePath ? file.webkitRelativePath.split("/") : [file.name];
            const path = directory ? parts.slice(1).join("/") : file.name;
            message("正在上传 " + path);
            await uploadBlob(targetProject, path, file);
        }
        await listFiles();
        message("上传完成");
    } finally {
        uploading = false;
        element("build").disabled = running;
        element("project").disabled = false;
        element("upload").disabled = false;
        element("folder").disabled = false;
        element("create").disabled = false;
    }
}

element("connect-form").onsubmit = handle(async () => {
    token = element("code").value.trim();
    await listProjects();
    sessionStorage.setItem("buildCode", token);
    element("login").hidden = true;
    element("workspace").hidden = false;
    element("disconnect").hidden = false;
    element("connection").textContent = "已连接";
    const tools = await api("tools");
    message(tools.compilerBundled || tools.compilerLoaded ? "已连接手机" :
        "已连接。请在手机工具链管理中检查组件安装状态。");
    await poll();
});
element("disconnect").onclick = handle(async () => {
    await leaveFile();
    generation++;
    token = "";
    sessionStorage.removeItem("buildCode");
    element("workspace").hidden = true;
    element("login").hidden = false;
    element("disconnect").hidden = true;
    element("connection").textContent = "未连接";
});
element("project").onchange = handle(async () => {
    const selected = element("project").value;
    try { await leaveFile(); }
    catch (error) { element("project").value = project; throw error; }
    await listProjects(selected);
});
element("create").onclick = handle(async () => {
    const name = prompt("项目名称");
    if (!name) return;
    await leaveFile();
    const result = await api("create", {name, productType:element("product-type").value});
    await listProjects(result.id);
});
element("content").oninput = () => { dirty = true; };
element("option-product").onchange = () => {element("tweak-options").hidden=element("option-product").value==="app";};
element("options-form").onsubmit = handle(async () => {
    if (!project) throw new Error("请选择项目");
    await leaveFile();
    const list = await api("files", {project});
    const config = list.files.includes("MobileCompiler.json") ?
        JSON.parse((await api("read", {project, path:"MobileCompiler.json"})).content) : {};
    if (!config || Array.isArray(config) || typeof config !== "object") throw new Error("MobileCompiler.json 应为 JSON 对象");
    const type = element("option-product").value;
    const schemes = ["rootless", "rootful", "roothide"].filter(scheme=>element("option-"+scheme).checked);
    const dylib = element("option-dylib").checked, deb = element("option-package").checked;
    if (type === "tweak" && !dylib && !deb) throw new Error("请选择独立 dylib 或 DEB");
    if (type === "tweak" && deb && !schemes.length) throw new Error("请选择至少一种 DEB 类型");
    Object.assign(config, {productType:type, exportDylib:dylib, package:type==="tweak"&&deb,
        cpuArchitecture:element("option-cpu").value, sdkVersion:element("option-sdk").value,
        deploymentTarget:element("option-minimum").value.trim()});
    if (schemes.length) {config.packageSchemes=schemes;config.packageScheme=schemes[0];}
    const content = JSON.stringify(config, null, 2) + "\n";
    await uploadBlob(project, "MobileCompiler.json", new Blob([content]));
    if (filename === "MobileCompiler.json") element("content").value=content;
    await listFiles();
    message("构建设置已保存，下一次构建生效");
});
element("save").onclick = handle(save);
element("new-file").onclick = handle(async () => {
    if (!project) throw new Error("请先新建项目");
    const path = prompt("相对路径，例如 Tweak.xm 或 MobileCompiler.json");
    if (!path) return;
    await leaveFile();
    const files = await api("files", {project});
    if (files.files.includes(path)) throw new Error("文件已存在，请在左侧打开");
    await api("write", {project, path, content:""});
    await listFiles();
});
element("build").onclick = handle(async () => {
    if (!project) throw new Error("请选择项目");
    await leaveFile();
    await api("build", {project});
    message("已提交到手机编译");
    await poll();
});
element("cancel").onclick = handle(async () => {
    await api("cancel", {job_id:currentJob});
    message("已请求取消，当前编译步骤结束后生效");
});
element("upload").onclick = () => element("files-input").click();
element("folder").onclick = () => element("folder-input").click();
element("files-input").onchange = handle(() => upload([...element("files-input").files], false));
element("folder-input").onchange = handle(() => upload([...element("folder-input").files], true));
window.addEventListener("beforeunload", event => {
    if (dirty) { event.preventDefault(); event.returnValue = ""; }
});
element("code").value = token;
setInterval(() => { if (!element("workspace").hidden) poll(); }, 1200);
