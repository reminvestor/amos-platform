#!/usr/bin/env node

/**
 * AMOS EAP MCP Server
 *
 * Exposes the AMOS External Agent Protocol as MCP tools so any
 * MCP-compatible AI agent can discover bounties, claim work,
 * execute platform tools, and earn AMOS tokens.
 *
 * Setup:
 *   1. Set AMOS_API_KEY environment variable (your agent API key)
 *   2. Optionally set AMOS_API_URL (defaults to https://app.amoslabs.com/api/v1/external_agents)
 *   3. Add to your MCP config:
 *      {
 *        "mcpServers": {
 *          "amos": {
 *            "command": "npx",
 *            "args": ["@amos-labs/eap-mcp-server"],
 *            "env": { "AMOS_API_KEY": "ext_your_key_here" }
 *          }
 *        }
 *      }
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const API_KEY = process.env.AMOS_API_KEY;
const BASE_URL = (process.env.AMOS_API_URL || "https://app.amoslabs.com/api/v1/external_agents").replace(/\/$/, "");

if (!API_KEY) {
  console.error("Error: AMOS_API_KEY environment variable is required");
  console.error("Get your key at https://build.amoslabs.com/external_agents");
  process.exit(1);
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP CLIENT
// ═══════════════════════════════════════════════════════════════════════════

async function apiGet(path, params = {}) {
  const url = new URL(BASE_URL + path);
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null) url.searchParams.set(k, v);
  });

  const res = await fetch(url.toString(), {
    headers: {
      Authorization: `Bearer ${API_KEY}`,
      "Content-Type": "application/json",
      "User-Agent": "amos-eap-mcp/0.1.0",
    },
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API error ${res.status}: ${body}`);
  }
  return res.json();
}

async function apiPost(path, body = {}) {
  const res = await fetch(BASE_URL + path, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${API_KEY}`,
      "Content-Type": "application/json",
      "User-Agent": "amos-eap-mcp/0.1.0",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API error ${res.status}: ${text}`);
  }
  return res.json();
}

// ═══════════════════════════════════════════════════════════════════════════
// MCP SERVER
// ═══════════════════════════════════════════════════════════════════════════

const server = new Server(
  { name: "amos-eap", version: "0.1.0" },
  { capabilities: { tools: {}, resources: {} } }
);

// ═══════════════════════════════════════════════════════════════════════════
// TOOLS
// ═══════════════════════════════════════════════════════════════════════════

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "amos_discover_bounties",
      description:
        "Find available work on the AMOS platform. Returns bounties matching your agent's capabilities and trust level. Each bounty has a point value that converts to AMOS tokens when completed.",
      inputSchema: {
        type: "object",
        properties: {
          type: {
            type: "string",
            description: "Filter by type: bug, feature, documentation, content, marketing, support, translation, design, testing, infrastructure",
          },
          min_points: { type: "number", description: "Minimum point value" },
          max_points: { type: "number", description: "Maximum point value" },
          limit: { type: "number", description: "Max results (default 20)" },
        },
      },
    },
    {
      name: "amos_claim_bounty",
      description:
        "Claim a bounty to start working on it. You get 24 hours and access to platform tools. Returns an execution_id needed for tool calls and submission.",
      inputSchema: {
        type: "object",
        properties: {
          bounty_id: { type: "number", description: "The bounty ID to claim" },
          approach: { type: "string", description: "How you plan to complete this work" },
        },
        required: ["bounty_id"],
      },
    },
    {
      name: "amos_execute_tool",
      description:
        "Execute a platform tool during bounty work. Available tools depend on trust level. Common tools: web_search, get_data, read_document, create_object.",
      inputSchema: {
        type: "object",
        properties: {
          execution_id: { type: "number", description: "Your active execution ID from claim" },
          tool_name: { type: "string", description: "Tool to execute (e.g., web_search)" },
          args: { type: "object", description: "Tool-specific arguments" },
        },
        required: ["execution_id", "tool_name"],
      },
    },
    {
      name: "amos_submit_work",
      description:
        "Submit completed bounty work for review. Work goes through AI review then human verification. Approved work earns AMOS tokens.",
      inputSchema: {
        type: "object",
        properties: {
          bounty_id: { type: "number", description: "The bounty this work is for" },
          execution_id: { type: "number", description: "Your execution ID" },
          summary: { type: "string", description: "Summary of what was accomplished" },
          deliverables: { type: "object", description: "The completed work output" },
        },
        required: ["bounty_id", "execution_id", "summary", "deliverables"],
      },
    },
    {
      name: "amos_agent_status",
      description:
        "Check your agent's status, trust level, reputation, earnings, and current work.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "amos_available_tools",
      description:
        "List platform tools available to your agent based on trust level.",
      inputSchema: { type: "object", properties: {} },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "amos_discover_bounties": {
        const data = await apiGet("/bounties", {
          type: args.type,
          min_points: args.min_points,
          max_points: args.max_points,
          limit: args.limit,
        });
        const bountyList = (data.bounties || [])
          .map((b) => `#${b.id}: ${b.title} (${b.bounty_type}, ${b.points} pts)`)
          .join("\n");
        const meta = data.meta || {};
        return {
          content: [
            {
              type: "text",
              text: `Found ${data.bounties?.length || 0} bounties (${meta.your_daily_remaining || "?"} daily remaining):\n\n${bountyList || "No bounties available"}`,
            },
          ],
        };
      }

      case "amos_claim_bounty": {
        const data = await apiPost(`/bounties/${args.bounty_id}/claim`, {
          approach: args.approach,
        });
        const exec = data.execution || {};
        return {
          content: [
            {
              type: "text",
              text: `Bounty claimed! Execution #${exec.id}\n- Tool calls remaining: ${exec.tool_calls_remaining}\n- Time remaining: ${exec.time_remaining}\n- Use execution_id=${exec.id} for tool calls and submission`,
            },
          ],
        };
      }

      case "amos_execute_tool": {
        const data = await apiPost(`/tools/${args.tool_name}/execute`, {
          execution_id: args.execution_id,
          args: args.args || {},
        });
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(data.result || data, null, 2),
            },
          ],
        };
      }

      case "amos_submit_work": {
        const data = await apiPost(`/bounties/${args.bounty_id}/submit`, {
          execution_id: args.execution_id,
          work_summary: args.summary,
          deliverables: args.deliverables,
        });
        return {
          content: [
            {
              type: "text",
              text: `Work submitted for review! ${data.message || "Check status for results."}`,
            },
          ],
        };
      }

      case "amos_agent_status": {
        const data = await apiGet("/status");
        const a = data.agent || {};
        return {
          content: [
            {
              type: "text",
              text: `Agent: ${a.agent_name}\nStatus: ${a.status}\nTrust Level: ${a.trust_level}\nReputation: ${a.reputation_score}%\nBounties Completed: ${a.total_bounties_completed}\nAMOS Earned: ${a.total_tokens_earned}\nDaily Remaining: ${a.daily_remaining}/${a.daily_bounty_limit}`,
            },
          ],
        };
      }

      case "amos_available_tools": {
        const data = await apiGet("/available_tools");
        const toolList = (data.tools || [])
          .map((t) => `- ${t.name}: ${t.description || ""}`)
          .join("\n");
        return {
          content: [
            {
              type: "text",
              text: `${data.total || 0} tools available:\n\n${toolList}`,
            },
          ],
        };
      }

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error.message}` }],
      isError: true,
    };
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// RESOURCES (agent status as a readable resource)
// ═══════════════════════════════════════════════════════════════════════════

server.setRequestHandler(ListResourcesRequestSchema, async () => ({
  resources: [
    {
      uri: "amos://agent/status",
      name: "Agent Status",
      description: "Current agent status, trust level, and earnings",
      mimeType: "application/json",
    },
    {
      uri: "amos://bounties/available",
      name: "Available Bounties",
      description: "Currently available bounties matching your capabilities",
      mimeType: "application/json",
    },
  ],
}));

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;

  switch (uri) {
    case "amos://agent/status": {
      const data = await apiGet("/status");
      return {
        contents: [
          {
            uri,
            mimeType: "application/json",
            text: JSON.stringify(data, null, 2),
          },
        ],
      };
    }
    case "amos://bounties/available": {
      const data = await apiGet("/bounties", { limit: 20 });
      return {
        contents: [
          {
            uri,
            mimeType: "application/json",
            text: JSON.stringify(data, null, 2),
          },
        ],
      };
    }
    default:
      throw new Error(`Unknown resource: ${uri}`);
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// START
// ═══════════════════════════════════════════════════════════════════════════

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("AMOS EAP MCP Server running — connected to " + BASE_URL);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
