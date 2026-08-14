#!/usr/bin/env python3
import json
import os
import sys
import time


def send(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def response(request_id, result):
    send({"jsonrpc": "2.0", "id": request_id, "result": result})


def update(session_id, payload):
    send(
        {
            "jsonrpc": "2.0",
            "method": "session/update",
            "params": {
                "sessionId": session_id,
                "update": payload,
            },
        }
    )


selected_config = {
    "model": "routing/router.startup-test",
    "thinking": "minimal",
}
active_workflow = None
nodes = []
session_count = 0


def config_options():
    return [
        {
            "id": "model",
            "name": "Model / routing",
            "category": "model",
            "type": "select",
            "currentValue": selected_config["model"],
            "options": [
                {"value": "routing/router.startup-test", "name": "Routing · Startup test"},
                {"value": "fixture/fixture/fixture-model", "name": "Fixture Model"},
            ],
        },
        {
            "id": "thinking",
            "name": "Thinking",
            "category": "thought_level",
            "type": "select",
            "currentValue": selected_config["thinking"],
            "options": [
                {"value": "minimal", "name": "Minimal"},
                {"value": "low", "name": "Low"},
                {"value": "medium", "name": "Medium"},
                {"value": "high", "name": "High"},
                {"value": "max", "name": "Max"},
            ],
        },
    ]


for raw_line in sys.stdin:
    raw_line = raw_line.strip()
    if not raw_line:
        continue
    message = json.loads(raw_line)
    method = message.get("method")
    request_id = message.get("id")
    params = message.get("params") or {}

    if method == "initialize":
        response(
            request_id,
            {
                "protocolVersion": 1,
                "agentCapabilities": {"mcpCapabilities": {"acp": True}},
            },
        )
    elif method == "_phenix/config/load":
        response(
            request_id,
            {
                "revision": 1,
                "definition_id": params["input"]["definition_id"],
                "router": params["input"]["router"],
            },
        )
    elif method == "_phenix/config/get":
        response(
            request_id,
            {
                "active": {
                    "revision": 1,
                    "definition_id": "phenix.startup-test",
                    "router": "router.startup-test",
                    "backend_ids": ["fixture"],
                    "workflows": [{"id": "workflow.startup-test", "title": "Startup integration workflow"}],
                    "workflow_count": 1,
                    "routing_table_count": 1,
                    "has_standard_session_template": True,
                    "mcp_server_count": 0,
                }
            },
        )
    elif method == "_phenix/backend/auth_provider/list":
        response(
            request_id,
            {
                "backend": params["backend"],
                "providers": [
                    {
                        "id": "fixture-login",
                        "display_name": "Fixture login",
                        "methods": ["terminal"],
                        "configured": False,
                        "source": "fixture",
                    }
                ],
            },
        )
    elif method == "_phenix/backend/auth/start":
        response(
            request_id,
            {
                "backend": params["backend"],
                "events": [
                    {
                        "kind": "external_command_requested",
                        "flow_id": "fixture-auth-flow",
                        "command": {
                            "program": "fixture-auth",
                            "arguments": ["login"],
                            "environment": {"FIXTURE_AUTH": "1"},
                        },
                    }
                ],
            },
        )
    elif method == "_phenix/backend/auth/terminal_finished":
        response(
            request_id,
            {
                "backend": params["backend"],
                "events": [
                    {
                        "kind": "auth_finished",
                        "flow_id": params["flow_id"],
                        "provider_id": "fixture-login",
                        "error": None if params["success"] else params.get("message"),
                    }
                ],
            },
        )
    elif method == "session/new":
        session_count += 1
        response(
            request_id,
            {
                "sessionId": "fixture-session-" + str(os.getpid()) + "-" + str(session_count),
                "configOptions": config_options(),
            },
        )
    elif method == "_phenix/session_tree/get":
        response(
            request_id,
            {
                "id": params["tree_id"],
                "definition_id": "phenix.harness",
                "root": "fixture-root",
                "nodes": nodes,
                "objectives": [],
                "active_workflow": active_workflow,
            },
        )
    elif method == "_phenix/workflow/start":
        active_workflow = params["workflow"]
        nodes.append(
            {
                "id": "fixture-workflow-root",
                "parent": "fixture-root",
                "role": "scout",
                "state": "running",
            }
        )
        response(request_id, {"objective_id": "fixture-workflow-objective", "root_node_id": "fixture-workflow-root"})
    elif method == "_phenix/node/delegate":
        node_id = "fixture-delegate-" + str(len(nodes) + 1)
        nodes.append(
            {
                "id": node_id,
                "parent": params["parent_node"],
                "role": params["role"],
                "state": "running",
            }
        )
        response(request_id, {"node_id": node_id})
    elif method == "_phenix/node/transcript/get":
        response(
            request_id,
            {
                "node_id": params["node_id"],
                "events": [],
                "edited_paths": ["fixture.lua"] if params["node_id"] == "fixture-root" else [],
            },
        )
    elif method == "session/set_config_option":
        config_id = params["configId"]
        if config_id in selected_config:
            selected_config[config_id] = params["value"]
        response(
            request_id,
            {"configOptions": config_options()},
        )
    elif method == "_phenix/node/execute":
        command = params.get("command") or {}
        if command.get("kind") == "steer":
            update(
                params["tree_id"],
                {
                    "sessionUpdate": "agent_message_chunk",
                    "content": {"type": "text", "text": "steered: " + command.get("text", "")},
                },
            )
        response(request_id, {"events": []})
    elif method == "session/prompt":
        prompt = params.get("prompt", [])
        text = "\n\n".join(
            block.get("text", "")
            for block in prompt
            if block.get("type") == "text"
        )
        image_count = sum(1 for block in prompt if block.get("type") == "image")
        update(
            params["sessionId"],
            {
                "sessionUpdate": "agent_thought_chunk",
                "content": {"type": "text", "text": "thinking about: " + text},
            },
        )

        if text == "scroll while streaming":
            time.sleep(0.25)

        if text == "render burst":
            for _ in range(200):
                update(
                    params["sessionId"],
                    {
                        "sessionUpdate": "agent_message_chunk",
                        "messageId": "render-burst",
                        "content": {"type": "text", "text": "x"},
                    },
                )
            response(request_id, {"stopReason": "end_turn"})
            continue

        if text == "rich transcript":
            update(
                params["sessionId"],
                {
                    "sessionUpdate": "tool_call",
                    "toolCallId": "fixture-tool",
                    "title": "read README",
                    "status": "in_progress",
                    "rawInput": {
                        "path": "README.md",
                        "query": "first line\nsecond line",
                    },
                },
            )
            update(
                params["sessionId"],
                {
                    "sessionUpdate": "tool_call_update",
                    "toolCallId": "fixture-tool",
                    "status": "completed",
                    "rawOutput": {"summary": "README contents"},
                },
            )
            assistant_text = "**done** with the tool call"
        else:
            assistant_text = "echo: " + text + " · images: " + str(image_count)

        update(
            params["sessionId"],
            {
                "sessionUpdate": "agent_message_chunk",
                "content": {"type": "text", "text": assistant_text},
            },
        )
        response(request_id, {"stopReason": "end_turn"})
    elif method == "session/close":
        response(request_id, {})
    elif request_id is not None:
        send(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32601, "message": "unknown method: " + str(method)},
            }
        )
