ObjC.import("Foundation");

function fail(message) { throw new Error(message); }

function readStdin() {
  const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  const text = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
  if (typeof text !== "string" || text.length === 0) fail("model list response is empty");
  return text;
}

function parseModels(text) {
  let payload;
  try { payload = JSON.parse(text); } catch (_) { fail("model list response is not valid JSON"); }
  if (Array.isArray(payload)) {
    const models = payload.filter(function (model) {
      return typeof model === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(model);
    });
    if (models.length === 0) fail("model list response contains no usable models");
    return models;
  }
  if (payload === null || typeof payload !== "object" || !Array.isArray(payload.data)) {
    fail("model list response has no data array");
  }
  const seen = {};
  const models = [];
  payload.data.forEach(function (entry) {
    if (entry === null || typeof entry !== "object" || typeof entry.id !== "string" ||
        !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(entry.id)) return;
    if (!seen[entry.id]) {
      seen[entry.id] = true;
      models.push(entry.id);
    }
  });
  if (models.length === 0) fail("model list response contains no usable models");
  return models;
}

function run(argv) {
  if (argv.length !== 1 || (argv[0] !== "list-json" && argv[0] !== "list-lines")) {
    fail("expected list-json or list-lines");
  }
  const models = parseModels(readStdin());
  return argv[0] === "list-json" ? JSON.stringify(models) : models.join("\n");
}
