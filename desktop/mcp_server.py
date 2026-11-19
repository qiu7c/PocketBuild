"""PocketBuild MCP bridge. The AI client runs this on Windows over stdio."""
import argparse
import base64
import io
import json
import os
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import ProxyHandler, Request, build_opener
from uuid import uuid4

from mcp.server.fastmcp import FastMCP


class Phone:
    def __init__(self, url: str, token: str, workspace: Path):
        parsed = urlsplit(url)
        if parsed.scheme != "http" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError("Use the HTTP address shown by PocketBuild on the phone.")
        if not token:
            raise ValueError("Supply --token or POCKETBUILD_TOKEN.")
        self.url = url.rstrip("/")
        self.token = token
        self.workspace = workspace.resolve(strict=True)
        if not self.workspace.is_dir():
            raise ValueError("workspace must be a local directory.")
        self.opener = build_opener(ProxyHandler({}))

    def local_path(self, path: str) -> Path:
        target = (self.workspace / path).resolve()
        if not target.is_relative_to(self.workspace):
            raise ValueError("Choose a path inside the configured workspace.")
        return target

    def request(self, action: str, **arguments) -> dict:
        body = json.dumps({"action": action, **arguments}).encode("utf-8")
        request = Request(
            self.url + "/api/v1/workspace", data=body,
            headers={"Content-Type": "application/json", "Authorization": "Bearer " + self.token},
        )
        try:
            with self.opener.open(request, timeout=60) as response:
                return json.load(response)
        except HTTPError as error:
            payload = error.read().decode("utf-8", errors="replace")
            try:
                message = json.loads(payload).get("error", payload)
            except ValueError:
                message = payload
            raise ValueError(f"Phone returned HTTP {error.code}: {message}") from None
        except URLError as error:
            raise ValueError(f"Cannot reach PocketBuild. Keep the phone app open and check its address. {error.reason}") from None

    def upload(self, project: str, relative: str, stream) -> int:
        upload = self.request("upload_begin", project=project, path=relative)["upload"]
        offset = 0
        try:
            while chunk := stream.read(512 * 1024):
                reply = self.request("upload_chunk", upload=upload, offset=offset,
                                     data=base64.b64encode(chunk).decode("ascii"))
                offset = reply["offset"]
            self.request("upload_finish", upload=upload, size=offset)
        except (OSError, ValueError, KeyError):
            # Abort the staging file while retaining the original project file.
            try:
                self.request("upload_abort", upload=upload)
            except (ValueError, OSError):
                pass
            raise
        return offset

    def download(self, job_id: str, name: str, directory: Path) -> Path:
        if name in ("", ".", "..") or Path(name).name != name or "/" in name or "\\" in name:
            raise ValueError("Phone returned an invalid artifact filename.")
        request = Request(
            self.url + "/download?" + urlencode({"job": job_id, "file": name}),
            headers={"Authorization": "Bearer " + self.token},
        )
        destination = directory / name
        temporary = directory / (".download-" + uuid4().hex)
        try:
            with self.opener.open(request, timeout=120) as response, temporary.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
        return destination


def create_server(phone: Phone) -> FastMCP:
    server = FastMCP("PocketBuild")

    @server.tool()
    def connect_device() -> dict:
        """Check the paired phone, app version and installed build components."""
        return phone.request("device")

    @server.tool()
    def list_projects() -> dict:
        """List projects stored in PocketBuild on the phone."""
        return phone.request("projects")

    @server.tool()
    def list_project_files(project_id: str) -> dict:
        """List relative source and resource paths in a phone project."""
        return phone.request("files", project=project_id)

    @server.tool()
    def create_project(name: str, product_type: str = "tweak") -> dict:
        """Create a phone project. product_type is tweak or app (programmatic UIKit template)."""
        if product_type not in ("tweak", "app"):
            raise ValueError("product_type must be tweak or app.")
        return phone.request("create", name=name, productType=product_type)

    @server.tool()
    def upload_project(directory: str, project_id: str = "", project_name: str = "") -> dict:
        """Upload a local project directory from the configured workspace in file chunks.
        Reuse project_id to upload into an existing project. .git, .theos, DerivedData and
        Python cache directories are skipped. Symlinks are skipped. Partial project uploads
        can be retried using the project ID returned in the error.
        """
        source = phone.local_path(directory)
        if not source.is_dir():
            raise ValueError("directory must be a project directory.")
        project = project_id or phone.request("create", name=project_name or source.name)["id"]
        count = 0
        byte_count = 0
        try:
            for folder, folders, files in os.walk(source, followlinks=False):
                folders[:] = [name for name in folders if name not in (
                    ".git", ".theos", "DerivedData", "__pycache__"
                ) and not (Path(folder) / name).is_symlink()]
                for name in files:
                    path = Path(folder) / name
                    if path.is_symlink():
                        continue
                    relative = path.relative_to(source).as_posix()
                    with path.open("rb") as stream:
                        byte_count += phone.upload(project, relative, stream)
                    count += 1
        except (OSError, ValueError) as error:
            raise ValueError(f"Upload stopped after {count} files in project {project}. Retry with project_id. {error}") from None
        return {"project_id": project, "files": count, "bytes": byte_count}

    @server.tool()
    def read_project_file(project_id: str, path: str) -> dict:
        """Read a UTF-8 project file from the phone."""
        return phone.request("read", project=project_id, path=path)

    @server.tool()
    def write_project_file(project_id: str, path: str, content: str) -> dict:
        """Save UTF-8 source/configuration on the phone using atomic chunked upload."""
        size = phone.upload(project_id, path, io.BytesIO(content.encode("utf-8")))
        return {"saved": True, "bytes": size}

    @server.tool()
    def start_build(project_id: str) -> dict:
        """Start a device build. App projects produce an unsigned IPA. Returns a job ID."""
        return phone.request("build", project=project_id)

    @server.tool()
    def get_build_status(job_id: str) -> dict:
        """Read build state, stage, progress and artifact names for a job."""
        result = phone.request("job", job_id=job_id)
        result.pop("log", None)
        return result

    @server.tool()
    def read_build_log(job_id: str, offset: int = 0) -> dict:
        """Read the build log starting at a character offset; use next_offset for subsequent reads."""
        if offset < 0:
            raise ValueError("offset must be nonnegative.")
        result = phone.request("job", job_id=job_id)
        log = result.get("log", "")
        return {"state": result["state"], "text": log[offset:], "next_offset": len(log)}

    @server.tool()
    def cancel_build(job_id: str) -> dict:
        """Request cancellation after the current compiler step."""
        return phone.request("cancel", job_id=job_id)

    @server.tool()
    def download_artifacts(job_id: str, output_directory: str = "artifacts") -> dict:
        """Download a completed job's artifacts into a job subdirectory inside the workspace."""
        if job_id in ("", ".", "..") or Path(job_id).name != job_id or "/" in job_id or "\\" in job_id:
            raise ValueError("Invalid job ID.")
        result = phone.request("job", job_id=job_id)
        if result["state"] in ("running", "idle"):
            raise ValueError("Wait for the build to finish.")
        directory = phone.local_path(output_directory) / job_id
        directory.mkdir(parents=True, exist_ok=True)
        paths = [str(phone.download(job_id, name, directory)) for name in result.get("artifacts", [])]
        return {"files": paths}

    return server


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--token", default=os.environ.get("POCKETBUILD_TOKEN", ""))
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()
    create_server(Phone(args.phone, args.token, args.workspace)).run(transport="stdio")


if __name__ == "__main__":
    main()
