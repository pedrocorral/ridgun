#!/usr/bin/env python3
import json
import re
import sys

def deny(reason: str) -> None:
    print(json.dumps({
        "decision": "deny",
        "reason": (
            "🛑 HOSTIA EN LA CARA — ACCIÓN BLOQUEADA POR EL HOOK DE SEGURIDAD:\n"
            f"Motivo: {reason}\n"
            "REGLA ABSOLUTA: Está TERMINANTEMENTE PROHIBIDO acceder a /proc, "
            "inspeccionar o parchear binarios/aplicaciones en ejecución o en disco "
            "(objdump, gdb, readelf, ptrace, hexdump, xxd, strace, ltrace, nm, strings, od, etc.) "
            "o modificar este hook. Solo puedes editar código fuente .rg y compilar con ridgunc/stable."
        )
    }, ensure_ascii=False))
    sys.exit(0)

def allow() -> None:
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

def main() -> None:
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            allow()
        payload = json.loads(raw)
    except Exception:
        allow()

    tool_call = payload.get("toolCall") or {}
    tool_name = str(tool_call.get("name", "")).lower()
    args = tool_call.get("args") or {}

    # Extraer ruta si la herramienta recibe Path / TargetFile / DirectoryPath
    path = str(
        args.get("Path")
        or args.get("TargetFile")
        or args.get("DirectoryPath")
        or args.get("SearchPath")
        or ""
    )

    # 1. Proteger el propio hook y su configuración contra modificaciones
    if any(k in tool_name for k in ("write", "edit", "replace")):
        if "hooks.json" in path or "safety-guard.sh" in path:
            deny(f"Intento de modificar o sobrescribir el hook de seguridad ({path}).")

    # 2. Bloquear cualquier acceso por ruta a /proc o lectura directa de binarios compilados
    if path:
        if path == "/proc" or path.startswith("/proc/") or "/proc/" in path:
            deny(f"Acceso a /proc detectado en ruta ({path}).")
        if any(k in tool_name for k in ("read", "view")):
            if re.search(r"/(bin|target)/(ridgunc|stable)($|[^.\w])", path):
                deny(f"Intento de leer un binario compilado directamente ({path}).")

    # 3. Bloquear en comandos de consola cualquier acceso a /proc, depuradores,
    #    desensambladores o inspección/parcheo de binarios/aplicaciones
    cmd = str(args.get("CommandLine") or args.get("command") or "")
    if cmd:
        if "hooks.json" in cmd or "safety-guard.sh" in cmd:
            deny("Intento de manipular hooks.json / safety-guard.sh desde consola.")

        if re.search(r"(^|[\s\"'=:/])/proc(/|$|[\s\"'])", cmd) or "procfs" in cmd:
            deny("Acceso general a /proc detectado en el comando.")

        forbidden_tools = [
            (r"\bptrace\b", "uso de ptrace"),
            (r"\bprocess_vm_readv\b", "uso de process_vm_readv"),
            (r"\bprocess_vm_writev\b", "uso de process_vm_writev"),
            (r"\bobjdump\b", "uso de objdump"),
            (r"\breadelf\b", "uso de readelf"),
            (r"\bgdb\b", "uso de gdb"),
            (r"\blldb\b", "uso de lldb"),
            (r"\bstrace\b", "uso de strace"),
            (r"\bltrace\b", "uso de ltrace"),
            (r"\bhexdump\b", "uso de hexdump"),
            (r"\bxxd\b", "uso de xxd"),
            (r"\bndisasm\b", "uso de ndisasm"),
            (r"\bobjcopy\b", "uso de objcopy"),
            (r"\bnm\b", "uso de nm sobre binarios"),
            (r"\bstrings\b", "uso de strings sobre binarios"),
            (r"\bod\b\s+-", "uso de od para volcar bytes"),
        ]
        for pattern, desc in forbidden_tools:
            if re.search(pattern, cmd):
                deny(f"Herramienta de inspección de aplicaciones/binarios prohibida ({desc}).")

        # Bloquear apertura/lectura/escritura de binarios ELF en scripts inline (python, perl, etc.)
        if re.search(r"open\s*\([^)]*(/tmp/|target/|bin/)[^)]*['\"][rwab+]+['\"]", cmd):
            if not re.search(r"\.(rg|md|json|txt|sh|yaml|yml|py|html|css)['\"]", cmd):
                deny("Intento de abrir, inspeccionar o parchear un binario ejecutable desde un script.")

    allow()

if __name__ == "__main__":
    main()
