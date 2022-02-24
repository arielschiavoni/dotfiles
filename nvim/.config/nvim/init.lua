local present, impatient = pcall(require, "impatient")

if present then
  impatient.enable_profile()
end

require("user.core.settings")
require("user.core.keymaps")
require("user.core.plugins")
