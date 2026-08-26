try
  set dialogResult to display dialog "Enter the API key" default answer "" with hidden answer buttons {"Cancel", "Save"} default button "Save" cancel button "Cancel"
  return "accepted:" & (text returned of dialogResult)
on error number -128
  return "cancelled"
end try
