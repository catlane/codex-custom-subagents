function fail(message) { throw new Error(message); }

function run(argv) {
  if (argv.length !== 1) fail("expected model list");
  let models;
  try { models = JSON.parse(argv[0]); } catch (_) { fail("model list is not valid JSON"); }
  if (!Array.isArray(models) || models.length === 0) fail("model list is empty");

  const app = Application.currentApplication();
  app.includeStandardAdditions = true;
  const selected = app.chooseFromList($(models), {
    withPrompt: "Select a model",
    title: "Codex custom subagent",
    defaultItems: [$(models[0])],
    multipleSelectionsAllowed: false,
    emptySelectionAllowed: false,
  });
  if (selected === false || selected.length === 0) return "cancelled";
  return ObjC.unwrap(selected[0]);
}
