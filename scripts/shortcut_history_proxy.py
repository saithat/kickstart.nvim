"""Stream an Ollama shortcut answer to gen.nvim and save the exchange as JSONL."""

import datetime
import fcntl
import json
import os
import re
import sys
import time
import uuid
from pathlib import Path
from urllib.request import Request, urlopen


OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
LITERAL_PERCENT = "\x1d"
LITERAL_DOLLAR = "\x1e"


def emit(chunk):
    sys.stdout.write(json.dumps(chunk, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def save(path, record):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.chmod(path, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        with os.fdopen(fd, "a", encoding="utf-8") as history:
            fd = -1
            history.write(json.dumps(record, ensure_ascii=False) + "\n")
            history.flush()
            os.fsync(history.fileno())
    finally:
        if fd >= 0:
            os.close(fd)


def context_from(prompt):
    filetype = re.search(r"The active buffer has filetype ([^.]+)\.", prompt)
    mappings = re.search(
        r"Active mappings \(mode \| keys to press in order \| action\):\n(.*?)\n\nQuestion:",
        prompt,
        re.DOTALL,
    )
    question = re.search(r"\nQuestion: (.*?)\n\n", prompt, re.DOTALL)
    return {
        "filetype": filetype.group(1) if filetype else None,
        "active_mappings": mappings.group(1) if mappings else None,
    }, question.group(1) if question else None


def main():
    history_path = Path(sys.argv[1])
    body_arg = sys.argv[2]
    body_json = Path(body_arg[1:]).read_text(encoding="utf-8") if body_arg.startswith("@") else body_arg
    body = json.loads(body_json)
    for message in body.get("messages", []):
        if isinstance(message.get("content"), str):
            message["content"] = (
                message["content"].replace(LITERAL_PERCENT, "%").replace(LITERAL_DOLLAR, "$")
            )

    prompt = body["messages"][-1]["content"]
    context, question = context_from(prompt)
    record = {
        "schema_version": 1,
        "id": uuid.uuid4().hex,
        "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "question": question,
        "context": context,
        "request": body,
        "response": {"text": "", "thinking": ""},
        "latency_ms": None,
    }

    started = time.monotonic()
    final = None
    try:
        request = Request(
            OLLAMA_URL,
            data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        with urlopen(request, timeout=240) as response:
            for line in response:
                chunk = json.loads(line)
                message = chunk.get("message") or {}
                record["response"]["text"] += message.get("content") or ""
                record["response"]["thinking"] += message.get("thinking") or ""
                if chunk.get("done"):
                    final = chunk
                    break
                emit(chunk)
        if final is None:
            raise RuntimeError("Ollama ended the response before completion")
        record["latency_ms"] = round((time.monotonic() - started) * 1000)
        record["response"]["done_reason"] = final.get("done_reason")
        record["response"]["prompt_tokens"] = final.get("prompt_eval_count")
        record["response"]["output_tokens"] = final.get("eval_count")
        record["response"]["total_duration_ns"] = final.get("total_duration")
        try:
            save(history_path, record)
        except OSError as exc:
            final.setdefault("message", {})["content"] = (
                (final.get("message") or {}).get("content") or ""
            ) + f"\n[Could not save shortcut history: {exc}]"
        emit(final)
    except Exception as exc:
        record["latency_ms"] = round((time.monotonic() - started) * 1000)
        record["response"]["error"] = str(exc)
        try:
            save(history_path, record)
        except OSError:
            pass
        emit({"message": {"content": f"Shortcut assistant failed: {exc}"}, "done": True})
        raise SystemExit(1)


if __name__ == "__main__":
    main()
