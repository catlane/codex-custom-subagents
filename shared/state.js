ObjC.import("Foundation");
const fm = $.NSFileManager.defaultManager;
function fail(message) { throw new Error(message); }
function readText(path) {
  const data = fm.contentsAtPath(path);
  return data.isNil() ? null : ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
}
function fileTypeAt(path) {
  const attributes = fm.attributesOfItemAtPathError(path, null);
  return attributes.isNil() ? null : ObjC.unwrap(attributes.objectForKey($.NSFileType));
}
function readRequiredRegularFile(path, name) {
  const fileType = fileTypeAt(path);
  if (fileType === "NSFileTypeSymbolicLink") fail(name + " must not be a symbolic link");
  if (fileType !== "NSFileTypeRegular") fail(name + " must be a readable regular file");
  const text = readText(path);
  if (text === null) fail(name + " must be a readable regular file");
  return text;
}
function stateAt(path, requireReadable) {
  const text = readText(path);
  if (text === null) {
    if (requireReadable) fail("could not read state registry");
    return { version: 1, agents: [] };
  }
  let state;
  try { state = JSON.parse(text); } catch (_) { fail("state registry is not valid JSON"); }
  const allowed = {
    agents: true,
    base_catalog_path: true,
    base_catalog_source: true,
    base_catalog_source_kind: true,
    catalog_path: true,
    initial_agents_shape: true,
    initial_config_shape: true,
    original_model_catalog_line: true,
    primary_model: true,
    version: true
  };
  if (state.version !== 1 || !Array.isArray(state.agents)) fail("unsupported state registry schema");
  Object.keys(state).forEach(function (key) {
    if (!allowed[key] || /(api.?key|secret|token|password)/i.test(key)) fail("invalid state registry field");
  });
  if (Object.prototype.hasOwnProperty.call(state, "catalog_path") &&
      (typeof state.catalog_path !== "string" || state.catalog_path.length === 0)) fail("invalid catalog path");
  ["catalog_path", "base_catalog_path", "base_catalog_source"].forEach(function (key) {
    if (typeof state[key] !== "string" || state[key].charAt(0) !== "/") fail("invalid state registry path");
  });
  if (["config", "default-cache", "test-override"].indexOf(state.base_catalog_source_kind) === -1) {
    fail("invalid base catalog source kind");
  }
  validateScalar(state.primary_model, "primary model");
  if (Object.prototype.hasOwnProperty.call(state, "original_model_catalog_line") &&
      state.original_model_catalog_line !== null && typeof state.original_model_catalog_line !== "string") fail("invalid original catalog line");
  if (!Object.prototype.hasOwnProperty.call(state, "initial_agents_shape")) {
    fail("state registry is missing initial AGENTS shape; restore from backup or reconfigure custom subagents");
  }
  if (["absent", "empty", "ends-newline", "no-final-newline"].indexOf(state.initial_agents_shape) === -1) {
    fail("state registry has invalid initial AGENTS shape; restore from backup or reconfigure custom subagents");
  }
  if (["absent", "empty", "ends-newline", "no-final-newline"].indexOf(state.initial_config_shape) === -1) {
    fail("state registry has invalid initial config shape; restore from backup or reconfigure custom subagents");
  }
  state.agents.forEach(validateAgent);
  const seenIds = {};
  state.agents.forEach(function (agent) {
    if (seenIds[agent.id]) fail("duplicate state agent ID");
    seenIds[agent.id] = true;
  });
  return state;
}
function sorted(value) {
  if (Array.isArray(value)) return value.map(sorted);
  if (value !== null && typeof value === "object") {
    const result = {};
    Object.keys(value).sort().forEach(function (key) { result[key] = sorted(value[key]); });
    return result;
  }
  return value;
}
function json(value) { return JSON.stringify(sorted(value), null, 2); }
function jsonPreservingOrder(value) { return JSON.stringify(value, null, 2); }
function validateScalar(value, name) {
  if (typeof value !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)) {
    fail("invalid " + name);
  }
}
function validateEndpoint(endpoint) {
  if (typeof endpoint !== "string" || /[\r\n]/.test(endpoint)) fail("invalid endpoint");
  const lower = endpoint.toLowerCase();
  if (/(api_key|apikey|token|secret|password|authorization|bearer|[?#@])/.test(lower)) {
    fail("endpoint contains credentials or secret-like text");
  }
  const match = /^(https?):\/\/([A-Za-z0-9.-]+)(?::([0-9]+))?(\/[A-Za-z0-9._~!$&'()*+,;=%/-]*)?$/.exec(endpoint);
  if (match === null || (match[4] && match[4].indexOf("..") !== -1)) fail("invalid endpoint");
  if (match[1] === "http" && match[2] !== "localhost" && match[2] !== "127.0.0.1") {
    fail("HTTP endpoint must be localhost");
  }
}
function agentFromJson(text) {
  let agent;
  try { agent = JSON.parse(text); } catch (_) { fail("invalid agent record"); }
  validateAgent(agent);
  return agent;
}
function validateAgent(agent) {
  const allowed = { endpoint: true, id: true, model: true, provider: true, role: true };
  if (agent === null || typeof agent !== "object" || Array.isArray(agent)) fail("invalid agent record");
  Object.keys(agent).forEach(function (key) {
    if (!allowed[key] || /(api.?key|secret|token|password)/i.test(key)) fail("agent records contain an invalid field");
  });
  validateScalar(agent.id, "agent ID");
  validateScalar(agent.role, "agent role");
  validateScalar(agent.provider, "agent provider");
  validateScalar(agent.model, "agent model");
  validateEndpoint(agent.endpoint);
}
function textShape(path, text) {
  if (!fm.fileExistsAtPath(path)) return "absent";
  if (text.length === 0) return "empty";
  return text.charAt(text.length - 1) === "\n" ? "ends-newline" : "no-final-newline";
}
function decodeTomlString(value, name) {
  try { return JSON.parse('"' + value + '"'); } catch (_) { fail("malformed top-level " + name + " setting"); }
}
function configAt(path, fallbackPrimary) {
  const exists = fm.fileExistsAtPath(path);
  if (exists && fileTypeAt(path) !== "NSFileTypeRegular") fail("config must be a regular file");
  const text = exists ? readText(path) : "";
  if (text === null) fail("config is unreadable");
  const records = [];
  let offset = 0;
  while (offset < text.length) {
    let lineEnd = text.indexOf("\n", offset);
    const fullEnd = lineEnd === -1 ? text.length : lineEnd + 1;
    if (lineEnd === -1) lineEnd = text.length;
    let contentEnd = lineEnd;
    if (contentEnd > offset && text.charAt(contentEnd - 1) === "\r") contentEnd -= 1;
    records.push({ start: offset, contentEnd: contentEnd, fullEnd: fullEnd, text: text.slice(offset, contentEnd) });
    offset = fullEnd;
  }
  let primary = null;
  let catalog = null;
  let catalogRecord = null;
  let inTopLevel = true;
  let firstTableOffset = null;
  records.forEach(function (record) {
    const line = record.text;
    if (inTopLevel && /^\s*\[/.test(line)) {
      inTopLevel = false;
      firstTableOffset = record.start;
    }
    if (!inTopLevel) {
      const ambiguous = /^\s*(model|model_catalog_json)\s*=/.exec(line);
      if (ambiguous !== null) fail("ambiguous non-top-level " + ambiguous[1] + " setting");
      return;
    }
    if (/^\s*(?:#|$)/.test(line)) return;
    const candidate = /^\s*(model|model_catalog_json)\s*=/.exec(line);
    if (candidate === null) return;
    const parsed = /^\s*(model|model_catalog_json)\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$/.exec(line);
    if (parsed === null) fail("malformed top-level " + candidate[1] + " setting");
    const value = decodeTomlString(parsed[2], parsed[1]);
    if (typeof value !== "string" || value.length === 0) fail("invalid top-level " + parsed[1] + " setting");
    if (parsed[1] === "model") {
      if (primary !== null) fail("duplicate top-level model settings");
      primary = value;
    } else {
      if (catalog !== null) fail("duplicate top-level model_catalog_json settings");
      catalog = value;
      catalogRecord = record;
    }
  });
  if (primary === null && fallbackPrimary) primary = fallbackPrimary;
  validateScalar(primary, "primary model");
  if (catalog !== null && catalog.charAt(0) !== "/") fail("model catalog source must be absolute");
  return {
    text: text,
    shape: textShape(path, text),
    primary_model: primary,
    catalog_path: catalog,
    catalog_record: catalogRecord,
    first_table_offset: firstTableOffset
  };
}
function writeRaw(path, text) {
  const data = $(text).dataUsingEncoding($.NSUTF8StringEncoding);
  if (!data.writeToFileAtomically(path, true)) fail("could not write rendered file");
}
function renderConfigToFile(configPath, catalogPath, outputPath, fallbackPrimary) {
  if (catalogPath.charAt(0) !== "/") fail("managed catalog path must be absolute");
  const config = configAt(configPath, fallbackPrimary);
  const managedLine = 'model_catalog_json = "' + tomlString(catalogPath) + '"';
  let output;
  if (config.catalog_record !== null) {
    output = config.text.slice(0, config.catalog_record.start) + managedLine + config.text.slice(config.catalog_record.contentEnd);
  } else if (config.shape === "absent" || config.shape === "empty") {
    output = 'model = "' + tomlString(config.primary_model) + '"\n' + managedLine + "\n";
  } else if (config.first_table_offset !== null) {
    output = config.text.slice(0, config.first_table_offset) + managedLine + "\n" + config.text.slice(config.first_table_offset);
  } else if (config.shape === "ends-newline") {
    output = config.text + managedLine + "\n";
  } else {
    output = config.text + "\n" + managedLine;
  }
  writeRaw(outputPath, output);
}
function restoreConfigToFile(configPath, statePath, outputPath) {
  const state = stateAt(statePath);
  const config = configAt(configPath, state.primary_model);
  const record = config.catalog_record;
  if (record === null || config.catalog_path !== state.catalog_path) fail("managed model_catalog_json setting does not match state");
  let output;
  if (state.original_model_catalog_line !== null) {
    output = config.text.slice(0, record.start) + state.original_model_catalog_line + config.text.slice(record.contentEnd);
  } else if (state.initial_config_shape === "absent" || state.initial_config_shape === "empty") {
    output = "";
  } else if (state.initial_config_shape === "ends-newline") {
    output = config.text.slice(0, record.start) + config.text.slice(record.fullEnd);
  } else {
    if (record.fullEnd !== config.text.length || record.start === 0 || config.text.charAt(record.start - 1) !== "\n") {
      fail("managed model_catalog_json setting is not final");
    }
    output = config.text.slice(0, record.start - 1);
  }
  writeRaw(outputPath, output);
}
function keychainBindingStatus(path, agentId, requestedEndpoint) {
  validateScalar(agentId, "agent ID");
  validateEndpoint(requestedEndpoint);
  if (!fm.fileExistsAtPath(path)) fail("state registry is missing");
  const attributes = fm.attributesOfItemAtPathError(path, null);
  if (attributes.isNil()) fail("could not inspect state registry");
  const fileType = ObjC.unwrap(attributes.objectForKey($.NSFileType));
  if (fileType === "NSFileTypeSymbolicLink") {
    fail("state registry must not be a symbolic link");
  }
  if (fileType !== "NSFileTypeRegular") fail("state registry is not a regular file");
  const matches = stateAt(path, true).agents.filter(function (agent) { return agent.id === agentId; });
  if (matches.length === 0) return "absent";
  return matches[0].endpoint === requestedEndpoint ? "match" : "mismatch";
}
function catalogAt(path, name) {
  const text = readRequiredRegularFile(path, name);
  let catalog;
  try { catalog = JSON.parse(text); } catch (_) { fail(name + " is not valid JSON"); }
  if (catalog === null || typeof catalog !== "object" || Array.isArray(catalog) || !Array.isArray(catalog.models)) {
    fail("invalid " + name);
  }
  const seen = {};
  catalog.models.forEach(function (entry) {
    if (entry === null || typeof entry !== "object" || Array.isArray(entry) ||
        typeof entry.slug !== "string" || entry.slug.length === 0) fail("invalid catalog model");
    if (seen[entry.slug]) fail("duplicate catalog model slug");
    seen[entry.slug] = true;
  });
  return catalog;
}
function selectedCatalog(catalog, primaryModel) {
  const matches = catalog.models.filter(function (entry) { return entry.slug === primaryModel; });
  if (matches.length !== 1) fail("primary model must appear exactly once in catalog");
  const generated = JSON.parse(JSON.stringify(catalog));
  generated.models.forEach(function (entry) {
    if (entry.slug === primaryModel) entry.multi_agent_version = "v1";
  });
  return generated;
}
function renderCatalog(basePath, primaryModel) {
  validateScalar(primaryModel, "primary model");
  return jsonPreservingOrder(selectedCatalog(catalogAt(basePath, "base model catalog"), primaryModel));
}
function validateCatalogMatchesState(statePath, basePath, catalogPath) {
  const state = stateAt(statePath);
  if (state.base_catalog_path !== basePath || state.catalog_path !== catalogPath) fail("catalog paths do not match state");
  const expected = selectedCatalog(catalogAt(basePath, "base model catalog"), state.primary_model);
  const actual = catalogAt(catalogPath, "managed catalog");
  if (JSON.stringify(actual) !== JSON.stringify(expected)) fail("managed catalog does not match state");
}
function workflow(state) {
  const lines = [
    "<!-- BEGIN custom-subagents managed workflow -->", "## Custom subagents", "",
    "Direct user instructions and repository AGENTS.md rules take precedence.",
    "Explicit no-subagents requests stay in the main task.",
    "Official subagents use GPT default, worker, or explorer roles in the same V1 task.",
    "One task never mixes V1 and V2.",
    "Otherwise, prefer installed custom agents automatically for nontrivial tasks."
  ];
  state.agents.slice().sort(function (a, b) { return a.id.localeCompare(b.id); }).forEach(function (agent) {
    const type = agent.id.replace(/-/g, "_");
    if (agent.role === "development") {
      lines.push("development agent type: " + type + "; use for bounded implementation or investigation with scoped ownership and focused verification.");
    } else if (agent.role === "review") {
      lines.push("review agent type: " + type + "; run independent findings-first review after nontrivial changes, read-only by default; actionable findings return for repair and re-review.");
    } else {
      lines.push("installed " + agent.role + " agent type: " + type + ".");
    }
  });
  lines.push("<!-- END custom-subagents managed workflow -->");
  return lines.join("\n");
}
function updateState(path, agentJson, catalogPath, baseCatalogPath, baseCatalogSource, baseCatalogSourceKind,
                     primaryModel, originalCatalogLine, initialAgentsShape, initialConfigShape) {
  const state = stateAt(path);
  const agent = agentFromJson(agentJson);
  const agents = state.agents.filter(function (entry) { return entry.id !== agent.id; });
  agents.push(agent);
  agents.sort(function (a, b) { return a.id.localeCompare(b.id); });
  state.agents = agents;
  state.catalog_path = catalogPath;
  state.base_catalog_path = baseCatalogPath;
  state.base_catalog_source = baseCatalogSource;
  state.base_catalog_source_kind = baseCatalogSourceKind;
  state.primary_model = primaryModel;
  if (!Object.prototype.hasOwnProperty.call(state, "original_model_catalog_line")) state.original_model_catalog_line = JSON.parse(originalCatalogLine);
  if (!Object.prototype.hasOwnProperty.call(state, "initial_agents_shape")) state.initial_agents_shape = initialAgentsShape;
  if (!Object.prototype.hasOwnProperty.call(state, "initial_config_shape")) state.initial_config_shape = initialConfigShape;
  [catalogPath, baseCatalogPath, baseCatalogSource].forEach(function (value) {
    if (typeof value !== "string" || value.charAt(0) !== "/") fail("invalid lifecycle path");
  });
  if (["config", "default-cache", "test-override"].indexOf(baseCatalogSourceKind) === -1) fail("invalid base catalog source kind");
  validateScalar(primaryModel, "primary model");
  if (["absent", "empty", "ends-newline", "no-final-newline"].indexOf(initialConfigShape) === -1) fail("invalid initial config shape");
  return state;
}
function validateConfigMatchesState(statePath, configPath) {
  const state = stateAt(statePath);
  const config = configAt(configPath, null);
  if (config.primary_model !== state.primary_model) fail("active primary model does not match lifecycle state");
  if (config.catalog_path !== state.catalog_path) fail("managed model_catalog_json setting does not match state");
}
function writeState(path, output) {
  const directory = $(path).stringByDeletingLastPathComponent;
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(directory, true, $(), null);
  const temporary = path + ".tmp-" + $.NSProcessInfo.processInfo.processIdentifier;
  const data = $(json(JSON.parse(output)) + "\n").dataUsingEncoding($.NSUTF8StringEncoding);
  if (!data.writeToFileAtomically(temporary, true)) fail("could not write temporary state registry");
  if (fm.fileExistsAtPath(path)) fm.removeItemAtPathError(path, null);
  if (!fm.moveItemAtPathToPathError(temporary, path, null)) fail("could not replace state registry");
}
function tomlString(value) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t");
}
function boundedString(value, name, singleLine) {
  if (typeof value !== "string" || value.length === 0 || value.length > 12000 || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value) ||
      (singleLine && /[\r\n]/.test(value))) fail("invalid agent spec " + name);
}
function readSpec(path) {
  const text = readText(path);
  if (text === null) fail("agent spec is missing");
  let spec;
  try { spec = JSON.parse(text); } catch (_) { fail("agent spec is not valid JSON"); }
  const allowed = { schema_version: true, description: true, developer_instructions: true, provider_display_name: true, wire_api: true, model_reasoning_effort: true, sandbox_mode: true, approval_policy: true };
  if (spec === null || typeof spec !== "object" || Array.isArray(spec)) fail("invalid agent spec");
  Object.keys(spec).forEach(function (key) {
    if (!allowed[key] || /(api.?key|secret|token|password|authorization|bearer)/i.test(key)) fail("invalid agent spec field");
  });
  if (spec.schema_version !== 1 || spec.wire_api !== "responses") fail("invalid agent spec");
  boundedString(spec.description, "description", true);
  boundedString(spec.developer_instructions, "developer_instructions", false);
  boundedString(spec.provider_display_name, "provider_display_name", true);
  if (Object.prototype.hasOwnProperty.call(spec, "model_reasoning_effort") &&
      ["low", "medium", "high", "xhigh"].indexOf(spec.model_reasoning_effort) === -1) fail("invalid agent spec effort");
  const hasSandbox = Object.prototype.hasOwnProperty.call(spec, "sandbox_mode");
  const hasApproval = Object.prototype.hasOwnProperty.call(spec, "approval_policy");
  if (hasSandbox !== hasApproval || (hasSandbox && (spec.sandbox_mode !== "read-only" || spec.approval_policy !== "never"))) {
    fail("invalid agent spec read-only policy");
  }
  return spec;
}
function renderAgentSpec(specPath, values) {
  const spec = readSpec(specPath);
  validateAgent({ id: values.id, role: "spec", provider: values.provider, endpoint: values.endpoint, model: values.model });
  const lines = [
    'name = "' + tomlString(values.id.replace(/-/g, "_")) + '"',
    'description = "' + tomlString(spec.description) + '"',
    'developer_instructions = "' + tomlString(spec.developer_instructions) + '"',
    'model = "' + tomlString(values.model) + '"',
    'model_provider = "' + tomlString(values.provider) + '"',
    'model_catalog_json = "' + tomlString(values.catalog_path) + '"'
  ];
  if (spec.model_reasoning_effort) lines.push('model_reasoning_effort = "' + spec.model_reasoning_effort + '"');
  if (spec.sandbox_mode) lines.push('sandbox_mode = "read-only"', 'approval_policy = "never"');
  lines.push("", '[model_providers.' + values.provider + ']', 'name = "' + tomlString(spec.provider_display_name) + '"',
    'base_url = "' + tomlString(values.endpoint) + '"', 'wire_api = "responses"', 'requires_openai_auth = false', "",
    '[model_providers.' + values.provider + '.auth]', 'command = "/usr/bin/security"',
    'args = ["find-generic-password", "-w", "-s", "' + tomlString(values.keychain_service) + '", "-a", "api-key"]');
  return lines.join("\n");
}
function run(argv) {
  const command = argv[0];
  if (command === "read") return json(stateAt(argv[1]));
  if (command === "install-state") {
    return json(updateState(argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]));
  }
  if (command === "uninstall-state") {
    const state = stateAt(argv[1]);
    state.agents = state.agents.filter(function (entry) { return entry.id !== argv[2]; });
    return json(state);
  }
  if (command === "original-catalog-line") {
    const value = stateAt(argv[1]).original_model_catalog_line;
    return value === null || value === undefined ? "" : value;
  }
  if (command === "initial-agents-shape") {
    const value = stateAt(argv[1]).initial_agents_shape;
    if (typeof value !== "string") fail("state registry is missing initial AGENTS shape");
    return value;
  }
  if (command === "initial-config-shape") return stateAt(argv[1]).initial_config_shape;
  if (command === "primary-model") return stateAt(argv[1]).primary_model;
  if (command === "base-catalog-source") return stateAt(argv[1]).base_catalog_source;
  if (command === "base-catalog-source-kind") return stateAt(argv[1]).base_catalog_source_kind;
  if (command === "manifest-name") {
    const text = readText(argv[1]);
    if (text === null) fail("plugin ownership manifest is missing");
    let manifest;
    try { manifest = JSON.parse(text); } catch (_) { fail("plugin ownership manifest is not valid JSON"); }
    if (typeof manifest.name !== "string" || manifest.name.length === 0) fail("plugin ownership manifest has no name");
    return manifest.name;
  }
  if (command === "validate-agent-input") {
    validateAgent({ id: argv[1], role: argv[2], provider: argv[3], endpoint: argv[4], model: argv[5] });
    return "";
  }
  if (command === "validate-agent-id") {
    validateScalar(argv[1], "agent ID");
    return "";
  }
  if (command === "validate-endpoint") {
    validateEndpoint(argv[1]);
    return "";
  }
  if (command === "validate-lifecycle-state") {
    const state = stateAt(argv[1]);
    if (state.catalog_path !== argv[2] || state.base_catalog_path !== argv[3] ||
        !Object.prototype.hasOwnProperty.call(state, "original_model_catalog_line") ||
        !Object.prototype.hasOwnProperty.call(state, "initial_agents_shape") ||
        !Object.prototype.hasOwnProperty.call(state, "initial_config_shape")) {
      fail("state registry does not match managed lifecycle");
    }
    if (argv.length > 4 && state.agents.filter(function (agent) { return agent.id === argv[4]; }).length !== 1) {
      fail("state registry is missing or duplicates the managed agent");
    }
    return "";
  }
  if (command === "validate-catalog") {
    catalogAt(argv[1], "managed catalog");
    return "";
  }
  if (command === "validate-agent-matches-state") {
    const state = stateAt(argv[1]);
    const matches = state.agents.filter(function (agent) { return agent.id === argv[2]; });
    if (matches.length !== 1) fail("managed agent is missing or duplicated in state");
    const agent = matches[0];
    if (agent.role !== argv[3] || agent.provider !== argv[4] ||
        agent.endpoint !== argv[5] || agent.model !== argv[6]) {
      fail("managed agent TOML does not match state");
    }
    return "";
  }
  if (command === "agent-present") {
    const count = stateAt(argv[1]).agents.filter(function (agent) { return agent.id === argv[2]; }).length;
    return String(count === 1 ? 1 : 0);
  }
  if (command === "keychain-binding-status") {
    return keychainBindingStatus(argv[1], argv[2], argv[3]);
  }
  if (command === "validate-catalog-matches-state") {
    validateCatalogMatchesState(argv[1], argv[2], argv[3]);
    return "";
  }
  if (command === "validate-base-catalog") {
    validateScalar(argv[2], "primary model");
    selectedCatalog(catalogAt(argv[1], "base model catalog"), argv[2]);
    return "";
  }
  if (command === "config-primary") return configAt(argv[1], argv[2] || null).primary_model;
  if (command === "config-shape") return configAt(argv[1], argv[2] || null).shape;
  if (command === "config-original-catalog-line-json") {
    const config = configAt(argv[1], argv[2] || null);
    return JSON.stringify(config.catalog_record === null ? null : config.catalog_record.text);
  }
  if (command === "config-catalog-source") {
    const config = configAt(argv[1], argv[4] || null);
    const source = argv[3] || config.catalog_path || argv[2];
    if (typeof source !== "string" || source.charAt(0) !== "/") fail("model catalog source must be absolute");
    return source;
  }
  if (command === "config-catalog-source-kind") {
    const config = configAt(argv[1], argv[3] || null);
    return argv[2] ? "test-override" : (config.catalog_path === null ? "default-cache" : "config");
  }
  if (command === "render-config-to-file") {
    renderConfigToFile(argv[1], argv[2], argv[3], argv[4] || null);
    return "";
  }
  if (command === "restore-config-to-file") {
    restoreConfigToFile(argv[1], argv[2], argv[3]);
    return "";
  }
  if (command === "validate-config-state") {
    validateConfigMatchesState(argv[1], argv[2]);
    return "";
  }
  if (command === "render-agent-spec-args") {
    return renderAgentSpec(argv[1], { id: argv[2], provider: argv[3], endpoint: argv[4], model: argv[5], catalog_path: argv[6], keychain_service: argv[7] });
  }
  if (command === "render-agent-spec-state") {
    const state = stateAt(argv[2]);
    const agents = state.agents.filter(function (agent) { return agent.id === argv[3]; });
    if (agents.length !== 1) fail("managed agent is missing in state");
    const agent = agents[0];
    return renderAgentSpec(argv[1], { id: agent.id, provider: agent.provider, endpoint: agent.endpoint, model: agent.model, catalog_path: argv[4], keychain_service: argv[5] });
  }
  if (command === "write") { writeState(argv[1], argv[2]); return ""; }
  if (command === "catalog") return renderCatalog(argv[1], argv[2]);
  if (command === "workflow") return workflow(stateAt(argv[1]));
  fail("unknown state command");
}
