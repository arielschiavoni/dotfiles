local dap = require("dap")
local dap_install = require("dap-install")
local installation_path = vim.fn.stdpath("data") .. "/dapinstall/"
dap_install.setup({
  installation_path = installation_path,
})

-- node2 -> requires :DInstall node2
dap.adapters.node2 = {
  type = "executable",
  command = "node",
  args = { installation_path .. "/jsnode/vscode-node-debug2/out/src/nodeDebug.js" },
}

local node_js_ts_config = {
  {
    name = "Launch",
    type = "node2",
    request = "launch",
    program = "${file}",
    cwd = vim.fn.getcwd(),
    sourceMaps = true,
    protocol = "inspector",
    console = "integratedTerminal",
  },
  {
    -- For this to work you need to make sure the node process is started with the `--inspect` flag.
    name = "Attach to process",
    type = "node2",
    request = "attach",
    processId = require("dap.utils").pick_process,
  },
}

dap.configurations.typescript = node_js_ts_config
dap.configurations.javascript = node_js_ts_config

-- chrome -> requires :DInstall chrome
-- dap.adapters.chrome = {
--   type = "executable",
--   command = "node",
--   args = { installation_path .. "/chrome/vscode-chrome-debug/out/src/chromeDebug.js" },
-- }
--
-- local chrome_js_ts_config = {
--   {
--     type = "chrome",
--     request = "attach",
--     program = "${file}",
--     cwd = vim.fn.getcwd(),
--     sourceMaps = true,
--     protocol = "inspector",
--     port = 9222,
--     webRoot = "${workspaceFolder}",
--   },
-- }
--
-- dap.configurations.typescript = chrome_js_ts_config
-- dap.configurations.javascriptreact = chrome_js_ts_config
-- dap.configurations.typescriptreact = chrome_js_ts_config
