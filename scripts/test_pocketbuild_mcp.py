"""Exercise the real stdio MCP bridge against an authenticated phone HTTP fixture."""
import asyncio
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
from threading import Thread
import unittest
from urllib.parse import parse_qs, urlsplit
from uuid import uuid4

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[1]


class PhoneFixture(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, data, status=200):
        payload = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        if self.headers.get("Authorization") != "Bearer test-code":
            self.reply({"error": "Pairing code invalid"}, 401)
            return
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.calls.append(body)
        action = body["action"]
        if action == "device":
            self.reply({"name": "PocketBuild", "tools": {"installed": ["support", "sdk16"]}})
        elif action == "create":
            identifier = str(uuid4())
            self.server.projects[identifier] = {"name": body["name"], "files": {}}
            self.reply({"id": identifier, "name": body["name"]})
        elif action == "projects":
            self.reply({"projects": [{"id": key, "name": value["name"]} for key, value in self.server.projects.items()]})
        elif action == "rename_project":
            self.server.projects[body["project"]]["name"] = body["name"]
            self.reply({"id": body["project"], "name": body["name"]})
        elif action == "history":
            self.reply({"builds": [job for job in self.server.jobs.values() if job["project"] == body["project"]]})
        elif action == "files":
            self.reply({"files": list(self.server.projects[body["project"]]["files"])})
        elif action == "read":
            self.reply({"content": self.server.projects[body["project"]]["files"][body["path"]].decode()})
        elif action == "upload_begin":
            identifier = str(uuid4())
            self.server.uploads[identifier] = {"project": body["project"], "path": body["path"], "data": b""}
            self.reply({"upload": identifier})
        elif action == "upload_chunk":
            upload = self.server.uploads[body["upload"]]
            if self.server.fail_upload and body["offset"] > 0:
                self.reply({"error": "Disk full fixture"}, 500)
                return
            if len(upload["data"]) != body["offset"]:
                self.reply({"error": "Wrong offset"}, 409)
                return
            upload["data"] += base64.b64decode(body["data"])
            self.reply({"offset": len(upload["data"])})
        elif action == "upload_finish":
            upload = self.server.uploads.pop(body["upload"])
            assert len(upload["data"]) == body["size"]
            self.server.projects[upload["project"]]["files"][upload["path"]] = upload["data"]
            self.reply({"saved": True})
        elif action == "upload_abort":
            self.server.uploads.pop(body["upload"])
            self.reply({"aborted": True})
        elif action == "build":
            identifier = str(uuid4())
            state = "failed" if self.server.missing_sdk else "running"
            job = {"id": identifier, "project": body["project"], "state": state, "log": "编译开始\n", "artifacts": []}
            if self.server.missing_sdk:
                job["issue"] = {"kind": "components", "components": [{"id": "sdk16", "title": "iOS 16.4 SDK"}]}
            self.server.jobs[identifier] = job
            self.reply(job)
        elif action in ("job", "cancel"):
            job = self.server.jobs.get(body.get("job_id"))
            if not job:
                self.reply({"error": "Job not found"}, 404)
            else:
                if action == "cancel":
                    job["state"] = "cancelled"
                self.reply(job)
        else:
            self.reply({"error": "Unknown action"}, 404)

    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer test-code":
            self.reply({"error": "Pairing code invalid"}, 401)
            return
        query = parse_qs(urlsplit(self.path).query)
        job = self.server.jobs.get(query.get("job", [""])[0])
        if not job or query.get("file", [""])[0] not in job["artifacts"]:
            self.reply({"error": "Artifact not found"}, 404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(self.server.artifact)))
        self.end_headers()
        self.wfile.write(self.server.artifact)


class MCPTests(unittest.IsolatedAsyncioTestCase):
    async def test_stdio_build_workflow(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), PhoneFixture)
        server.projects, server.uploads, server.jobs, server.calls = {}, {}, {}, []
        server.fail_upload = False
        server.missing_sdk = False
        server.artifact = b"IPA transport fixture\x00" * 100000
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temporary:
                workspace = Path(temporary)
                project = workspace / "LocalApp"
                project.mkdir()
                (project / "main.m").write_text("// 中文源码\nint main(void) { return 0; }", encoding="utf-8")
                (project / "Large.bin").write_bytes(b"a" * 1200000)
                (project / ".git").mkdir()
                (project / ".git/config").write_text("skip")
                parameters = StdioServerParameters(command=sys.executable, args=[
                    str(ROOT / "desktop/mcp_server.py"), "--phone", f"http://127.0.0.1:{server.server_port}",
                    "--token", "test-code", "--workspace", str(workspace),
                ])
                async with stdio_client(parameters) as (read, write), ClientSession(read, write) as session:
                    await session.initialize()
                    tools = await session.list_tools()
                    self.assertIn("rename_project", {tool.name for tool in tools.tools})
                    self.assertIn("list_builds", {tool.name for tool in tools.tools})

                    async def call(tool_name, **arguments):
                        reply = await session.call_tool(tool_name, arguments)
                        self.assertFalse(reply.isError, reply.content)
                        return reply.structuredContent or json.loads(reply.content[0].text)

                    self.assertEqual((await call("connect_device"))["name"], "PocketBuild")
                    created = await call("create_project", name="Demo", product_type="app")
                    identifier = created["id"]
                    self.assertEqual(server.calls[-1]["productType"], "app")
                    uploaded = await call("upload_project", directory="LocalApp", project_id=identifier)
                    self.assertEqual(uploaded["files"], 2)
                    self.assertEqual(len(server.projects[identifier]["files"]["Large.bin"]), 1200000)
                    self.assertEqual(len(server.uploads), 0)
                    self.assertIn("main.m", (await call("list_project_files", project_id=identifier))["files"])
                    await call("write_project_file", project_id=identifier, path="main.m", content="// 新版本\n")
                    self.assertEqual((await call("read_project_file", project_id=identifier, path="main.m"))["content"], "// 新版本\n")

                    server.fail_upload = True
                    failure = await session.call_tool("upload_project", {"directory": "LocalApp", "project_id": identifier})
                    self.assertTrue(failure.isError)
                    self.assertEqual(server.uploads, {})
                    self.assertEqual(len(server.projects[identifier]["files"]["Large.bin"]), 1200000)
                    server.fail_upload = False

                    job = (await call("start_build", project_id=identifier))["id"]
                    status = await call("get_build_status", job_id=job)
                    self.assertEqual(status["state"], "running")
                    self.assertNotIn("log", status)
                    log = await call("read_build_log", job_id=job)
                    server.jobs[job]["log"] += "完成\n"
                    self.assertEqual((await call("read_build_log", job_id=job, offset=log["next_offset"]))["text"], "完成\n")
                    server.jobs[job].update(state="succeeded", artifacts=["Demo-unsigned.ipa"])
                    second = (await call("start_build", project_id=identifier))["id"]
                    await call("cancel_build", job_id=second)
                    self.assertEqual(server.jobs[second]["state"], "cancelled")
                    same_name = (await call("create_project", name="Demo", product_type="app"))["id"]
                    self.assertNotEqual(identifier, same_name)
                    renamed = await call("rename_project", project_id=identifier, name="Renamed")
                    self.assertEqual(renamed["id"], identifier)
                    history = await call("list_builds", project_id=identifier)
                    self.assertEqual({entry["id"] for entry in history["builds"]}, {job, second})
                    self.assertEqual((await call("list_builds", project_id=same_name))["builds"], [])
                    server.missing_sdk = True
                    rejected = await call("start_build", project_id=same_name)
                    self.assertEqual(rejected["state"], "failed")
                    self.assertEqual(rejected["issue"]["components"][0]["id"], "sdk16")
                    self.assertEqual((await call("get_build_status", job_id=rejected["id"]))["project"], same_name)
                    downloaded = await call("download_artifacts", job_id=job)
                    self.assertEqual(Path(downloaded["files"][0]).read_bytes(), server.artifact)
                    self.assertFalse(list(workspace.rglob(".download-*")))
                    for name, arguments in (
                        ("upload_project", {"directory": "../outside"}),
                        ("download_artifacts", {"job_id": job, "output_directory": "../outside"}),
                        ("get_build_status", {"job_id": "missing"}),
                    ):
                        self.assertTrue((await session.call_tool(name, arguments)).isError)
        finally:
            await asyncio.to_thread(server.shutdown)
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
