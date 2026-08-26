ObjC.import("Foundation");

function storeWithPrivatePipe(helper, service, account, secret) {
  const task = $.NSTask.alloc.init;
  const input = $.NSPipe.pipe;
  const nullOutput = $.NSFileHandle.fileHandleForWritingAtPath("/dev/null");

  task.launchPath = "/usr/bin/expect";
  task.arguments = $([helper, service, account]);
  task.standardInput = input;
  task.standardOutput = nullOutput;
  task.standardError = nullOutput;
  task.launch;

  const payload = $(secret + "\n").dataUsingEncoding($.NSUTF8StringEncoding);
  input.fileHandleForWriting.writeData(payload);
  input.fileHandleForWriting.closeFile;
  task.waitUntilExit;

  if (Number(task.terminationStatus) !== 0) {
    throw new Error(`Keychain storage failed with status ${task.terminationStatus}`);
  }
}

function run(argv) {
  if (argv.length !== 3 || argv[0].charAt(0) !== "/" ||
      !/^codex-custom-subagent\/[A-Za-z0-9-]+$/.test(argv[1]) || argv[2] !== "api-key") {
    throw new Error("invalid Keychain storage arguments");
  }
  const helperAttributes = $.NSFileManager.defaultManager.attributesOfItemAtPathError(argv[0], null);
  if (helperAttributes.isNil() || ObjC.unwrap(helperAttributes.objectForKey($.NSFileType)) !== "NSFileTypeRegular") {
    throw new Error("Keychain storage helper must be a regular file");
  }
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  try {
    const dialogResult = app.displayDialog("Enter the API key", {
      defaultAnswer: "",
      hiddenAnswer: true,
      buttons: ["Cancel", "Save"],
      defaultButton: "Save",
      cancelButton: "Cancel",
    });
    let secret = dialogResult.textReturned;
    if (secret.length === 0) return "empty";
    if (secret.length > 12000 || /[\r\n\u0000]/.test(secret)) {
      throw new Error("invalid API key value");
    }
    storeWithPrivatePipe(argv[0], argv[1], argv[2], secret);
    secret = "";
    return "stored";
  } catch (error) {
    if (error.errorNumber === -128) {
      return "cancelled";
    }
    throw error;
  }
}
