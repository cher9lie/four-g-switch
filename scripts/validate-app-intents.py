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
metadata = json.loads((directory / "extract.actionsdata").read_text(encoding="utf-8"))
actions = metadata["actions"]
missing = [name for name in expected if name not in actions or not actions[name].get("isDiscoverable")]
if missing:
    raise SystemExit("Missing exported App Intents types: " + ", ".join(missing))
entity = metadata["entities"]["FourGStatusEntity"]
properties = {value["identifier"] for value in entity["properties"]}
required_properties = {"mode", "summary", "connected", "busy", "configurationVerified", "preparedForWindows"}
if not required_properties.issubset(properties):
    raise SystemExit("Structured status fields are missing from exported metadata")
for name in expected[:4]:
    output = actions[name]["outputType"]["entity"]["wrapper"]["typeName"]
    if output != "FourGStatusEntity" or actions[name]["openAppWhenRun"]:
        raise SystemExit("Background status-returning action has invalid metadata: " + name)
for name in ("UseFourGOnMacIntent", "PrepareFourGForWindowsIntent", "SetFourGModeIntent"):
    if actions[name]["authenticationPolicy"] != 2:  # Apple's requiresLocalDeviceAuthentication
        raise SystemExit("Mode mutation is missing local-device authentication: " + name)
if not actions["OpenFourGPanelIntent"]["openAppWhenRun"]:
    raise SystemExit("Panel action must open the app")
parameters = actions["SetFourGModeIntent"]["parameters"]
if not any(value["name"] == "mode" and not value["isOptional"] for value in parameters):
    raise SystemExit("Explicit target-mode parameter was not exported")
shortcuts = metadata["autoShortcuts"]
shortcut_actions = {value["actionIdentifier"] for value in shortcuts}
if shortcut_actions != set(expected) - {"SetFourGModeIntent"} or len(shortcuts) != 4:
    raise SystemExit("Four App Shortcuts must be exported")
for shortcut in shortcuts:
    if not any("${applicationName}" in phrase["key"] for phrase in shortcut["phraseTemplates"]):
        raise SystemExit("App Shortcut is missing its application-name phrase")
result = {"verified": True, "actions": expected, "entity": "FourGStatusEntity",
          "status_properties": sorted(properties), "app_shortcuts": len(shortcuts),
          "metadata_files": [p.name for p in files]}
report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False))
