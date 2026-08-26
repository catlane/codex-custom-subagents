function run() {
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
    return `accepted:${dialogResult.textReturned}`;
  } catch (error) {
    if (error.errorNumber === -128) {
      return "cancelled";
    }
    throw error;
  }
}
