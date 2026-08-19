#!/usr/bin/env python3
import json
import sys

MODEL = {
    "backend": "fixture",
    "provider": "fixture",
    "model": "fixture-model",
    "inference": {"effort": None},
}
ALT_MODEL = {
    "backend": "fixture",
    "provider": "fixture",
    "model": "fixture-alt",
    "inference": {"effort": "high"},
}
SECOND_MODEL = {
    "backend": "fixture",
    "provider": "fixture-two",
    "model": "fixture-two-model",
    "inference": {"effort": "medium"},
}
CATALOG = {
    "backend": "fixture",
    "models": [
        {"target": MODEL, "name": "Fixture Model", "selectable": False},
        {"target": ALT_MODEL, "name": "Fixture Alt", "selectable": False},
        {"target": SECOND_MODEL, "name": "Fixture Two", "selectable": False},
    ],
    "authentication_state": "required",
    "authentication_methods": [
        {
            "id": "fixture-login",
            "backend": "fixture",
            "provider": "fixture",
            "kind": "agent",
            "name": "Fixture login",
            "description": "Deterministic native conductor authentication fixture",
            "selectable": True,
        },
        {
            "id": "fixture-two-login",
            "backend": "fixture",
            "provider": "fixture-two",
            "kind": "agent",
            "name": "Fixture two login",
            "description": "Second deterministic routing authentication fixture",
            "selectable": True,
        },
    ],
}
ROUTING_PROFILES = [
    {"id": "router.free", "providers": ["fixture"]},
    {"id": "router.mixed", "providers": ["fixture", "fixture-two"]},
]
SKILLS = [
    {
        "id": "unslop",
        "name": "unslop",
        "description": "Cut AI tells from any writing. Must always apply.",
        "invocation": "model_eligible",
    }
]


def callable_descriptor(callable_id, kind, description):
    return {
        "id": callable_id,
        "kind": kind,
        "description": description,
        "input_schema": {"type": "object"},
        "output_schema": {"type": "object"},
        "capabilities": [],
        "policy": {"requires_permission": False},
    }


CALLABLES = [
    callable_descriptor("tool.fixture", "tool", "Fixture-only tool metadata"),
    callable_descriptor("agent.fixture", "agent", "Deterministic fixture agent"),
    callable_descriptor("workflow.fixture", "workflow", "Deterministic fixture workflow"),
]
CALLABLE_BY_ID = {descriptor["id"]: descriptor for descriptor in CALLABLES}

sessions = {}
executions = {}
events = []
sequence = 0
next_session = 1
next_execution = 1


def write(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def snapshot():
    return {
        "sessions": list(sessions.values()),
        "executions": list(executions.values()),
        "last_event_sequence": sequence,
    }


def reply(request_id, result):
    write({"type": "response", "id": request_id, "status": "ok", "result": result})


def failure(request_id, code, message):
    write(
        {
            "type": "response",
            "id": request_id,
            "status": "error",
            "error": {
                "code": code,
                "message": message,
                "session_id": None,
                "execution_id": None,
            },
        }
    )


def emit(session_id, execution_id, kind):
    global sequence
    sequence += 1
    event = {
        "sequence": sequence,
        "session_id": session_id,
        "execution_id": execution_id,
        "kind": kind,
    }
    events.append(event)
    write({"type": "event", "event": event})


def set_state(execution, state):
    execution["state"] = state
    emit(
        execution["session_id"],
        execution["id"],
        {"type": "execution_state_changed", "state": state},
    )


def create_session(command):
    global next_session
    session_id = f"session-{next_session}"
    next_session += 1
    session = {
        "id": session_id,
        "parent_session": command.get("parent_session"),
        "name": command.get("name"),
        "config_revision": "fixture-revision",
        "default_target": command["target"],
    }
    sessions[session_id] = session
    return session


def create_execution(session, kind, callable_id=None, state="pending", parent_execution=None):
    global next_execution
    execution_id = f"execution-{next_execution}"
    next_execution += 1
    execution = {
        "id": execution_id,
        "session_id": session["id"],
        "parent_execution": parent_execution,
        "kind": kind,
        "callable": callable_id,
        "target": session["default_target"],
        "state": state,
    }
    executions[execution_id] = execution
    return execution


def submit(command):
    session = sessions.get(command["session_id"])
    if session is None:
        return None
    return create_execution(session, "root")


def start_callable(command):
    session = sessions.get(command.get("session_id"))
    descriptor = CALLABLE_BY_ID.get(command.get("callable"))
    if session is None or descriptor is None or descriptor["kind"] == "tool":
        return None
    return create_execution(session, descriptor["kind"], descriptor["id"])


def handle(message):
    command = message.get("command") or {}
    command_type = command.get("type")
    request_id = message.get("id", 0)

    if command_type == "initialize":
        after = command.get("after_sequence") or 0
        reply(
            request_id,
            {
                "type": "initialized",
                "snapshot": snapshot(),
                "events": [event for event in events if event["sequence"] > after],
                "backends": [CATALOG],
            },
        )
        return

    if command_type == "get_snapshot":
        reply(
            request_id,
            {"type": "snapshot", "snapshot": snapshot(), "backends": [CATALOG]},
        )
        return

    if command_type == "get_callable_catalog":
        reply(request_id, {"type": "callable_catalog", "callables": CALLABLES})
        return

    if command_type == "get_skill_catalog":
        reply(request_id, {"type": "skill_catalog", "skills": SKILLS})
        return

    if command_type == "get_routing_catalog":
        reply(request_id, {"type": "routing_catalog", "profiles": ROUTING_PROFILES})
        return

    if command_type == "create_session":
        session = create_session(command)
        reply(request_id, {"type": "session", "session": session})
        return

    if command_type == "fork_session":
        parent = sessions.get(command.get("session_id"))
        if parent is None:
            failure(request_id, "unknown_id", "unknown session")
            return
        session = create_session(
            {
                "parent_session": parent["id"],
                "name": command.get("name"),
                "target": parent["default_target"],
            }
        )
        reply(request_id, {"type": "session", "session": session})
        return

    if command_type == "rename_session":
        session = sessions.get(command.get("session_id"))
        if session is None:
            failure(request_id, "unknown_id", "unknown session")
            return
        session["name"] = command["name"]
        reply(request_id, {"type": "session", "session": session})
        return

    if command_type == "set_session_target":
        session = sessions.get(command.get("session_id"))
        if session is None:
            failure(request_id, "unknown_id", "unknown session")
            return
        session["default_target"] = command["target"]
        reply(request_id, {"type": "session", "session": session})
        return

    if command_type == "submit":
        execution = submit(command)
        if execution is None:
            failure(request_id, "unknown_id", "unknown session")
            return
        reply(request_id, {"type": "execution", "execution": execution})
        emit(
            execution["session_id"],
            execution["id"],
            {"type": "user_input", "text": command["text"]},
        )
        set_state(execution, "running")
        emit(
            execution["session_id"],
            execution["id"],
            {"type": "reasoning_delta", "text": "thinking about: " + command["text"]},
        )
        if command["text"] == "hold":
            return
        if command["text"] == "rich transcript":
            emit(
                execution["session_id"],
                execution["id"],
                {
                    "type": "tool_call_started",
                    "tool_call_id": "fixture-tool",
                    "callable": "read README",
                },
            )
            emit(
                execution["session_id"],
                execution["id"],
                {
                    "type": "tool_call_arguments",
                    "tool_call_id": "fixture-tool",
                    "arguments": '{"path":"README.md","note":"first line\\nsecond line"}',
                },
            )
            emit(
                execution["session_id"],
                execution["id"],
                {
                    "type": "tool_call_finished",
                    "tool_call_id": "fixture-tool",
                    "output": "README contents",
                    "success": True,
                },
            )
        emit(
            execution["session_id"],
            execution["id"],
            {"type": "assistant_content_delta", "text": "echo: " + command["text"]},
        )
        set_state(execution, "completed")
        return

    if command_type == "start_callable":
        execution = start_callable(command)
        if execution is None:
            failure(request_id, "invalid_request", "unknown or non-startable callable")
            return
        reply(request_id, {"type": "execution", "execution": execution})
        emit(
            execution["session_id"],
            execution["id"],
            {"type": "user_input", "text": command["objective"]},
        )
        set_state(execution, "running")
        emit(
            execution["session_id"],
            execution["id"],
            {
                "type": "reasoning_delta",
                "text": f"{execution['callable']} reasoning: {command['objective']}",
            },
        )
        emit(
            execution["session_id"],
            execution["id"],
            {
                "type": "assistant_content_delta",
                "text": f"{execution['callable']} result: {command['objective']}",
            },
        )
        set_state(execution, "completed")
        return

    if command_type == "cancel_execution":
        execution = executions.get(command.get("execution_id"))
        if execution is None:
            failure(request_id, "unknown_id", "unknown execution")
            return
        reply(request_id, {"type": "accepted"})
        set_state(execution, "cancelled")
        return

    if command_type == "refresh_backend_catalog":
        reply(request_id, {"type": "backend_catalog", "catalog": CATALOG})
        return

    if command_type == "select_authentication":
        if command.get("backend_id") != "fixture":
            failure(request_id, "unknown_id", "unknown authentication backend")
            return
        method = command.get("method_id")
        provider = {
            "fixture-login": "fixture",
            "fixture-two-login": "fixture-two",
        }.get(method)
        if provider is None:
            failure(request_id, "unknown_id", "unknown authentication method")
            return
        for model in CATALOG["models"]:
            if model["target"]["provider"] == provider:
                model["selectable"] = True
        CATALOG["authentication_state"] = (
            "authenticated"
            if any(model["selectable"] for model in CATALOG["models"])
            else "required"
        )
        reply(request_id, {"type": "backend_catalog", "catalog": CATALOG})
        return

    failure(request_id, "invalid_request", "unsupported command: " + str(command_type))


for raw_line in sys.stdin:
    raw_line = raw_line.strip()
    if not raw_line:
        continue
    try:
        handle(json.loads(raw_line))
    except Exception as error:
        failure(0, "invalid_request", str(error))