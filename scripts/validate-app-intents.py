"""Validate the output of Apple's compiler tool, not source declarations."""
import json
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
report = pathlib.Path(sys.argv[2])
expected = [
    "GetFourGStatusIntent",
    "UseFourGOnMacIntent",
    "PrepareFourGForWindowsIntent",
    "SetFourGModeIntent",
    "OpenFourGPanelIntent",
]
if not directory.is_dir():
    raise SystemExit("Metadata.appintents is missing from the actual app bundle")
files = [p for p in directory.rglob("*") if p.is_file()]
if not files:
    raise SystemExit("App Intents metadata bundle is empty")
texts = []
for path in files:
    data = path.read_bytes()
    text = data.decode("utf-8", errors="replace")
    try:
        parsed = json.loads(text)
        texts.append(json.dumps(parsed, ensure_ascii=False))
    except (ValueError, UnicodeError):
        texts.append(text)
combined = "\n".join(texts)
missing = [name for name in expected + ["FourGStatusEntity"] if name not in combined]
if missing:
    raise SystemExit("Missing exported App Intents types: " + ", ".join(missing))
result = {"verified": True, "actions": expected, "entity": "FourGStatusEntity", "metadata_files": [p.name for p in files]}
report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False))
