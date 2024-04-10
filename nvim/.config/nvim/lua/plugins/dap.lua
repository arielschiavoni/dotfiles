local js_based_languages = { "javascript", "typescript", "javascriptreact", "typescriptreact" }

return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      -- fancy UI for the debugger
      {
        "rcarriga/nvim-dap-ui",
        dependencies = { "nvim-neotest/nvim-nio" },
        keys = {
          {
            "<leader>du",
            function()
              require("dapui").toggle({ reset = true })
            end,
            desc = "Dap UI",
          },
          {
            "<leader>de",
            function()
              require("dapui").eval()
            end,
            desc = "Eval",
            mode = { "n", "v" },
          },
        },
        config = function()
          local dap = require("dap")
          local dapui = require("dapui")
          ---@diagnostic disable-next-line: missing-fields
          dapui.setup({
            layouts = {
              {
                -- You can change the order of elements in the sidebar
                elements = {
                  -- Provide IDs as strings or tables with "id" and "size" keys
                  {
                    id = "scopes",
                    size = 0.25, -- Can be float or integer > 1
                  },
                  { id = "breakpoints", size = 0.25 },
                  { id = "stacks", size = 0.25 },
                  { id = "watches", size = 0.25 },
                },
                size = 40,
                position = "left", -- Can be "left" or "right"
              },
              {
                elements = {
                  "repl",
                  -- "console",
                },
                size = 10,
                position = "bottom", -- Can be "bottom" or "top"
              },
            },
          })
          -- setup event listeners to open/close dap-ui when debug session is started or terminated
          dap.listeners.after.event_initialized["dapui_config"] = function()
            dapui.open({ reset = true })
          end
          dap.listeners.before.event_terminated["dapui_config"] = function()
            dapui.close({})
          end
          dap.listeners.before.event_exited["dapui_config"] = function()
            dapui.close({})
          end
        end,
      },

      -- virtual text for the debugger
      {
        "theHamsta/nvim-dap-virtual-text",
        opts = {},
      },

      -- use telescope to list variables, frames, breakpoints, etc
      {
        "nvim-telescope/telescope-dap.nvim",
        dependencies = {
          "nvim-telescope/telescope.nvim",
        },
        config = function()
          require("telescope").load_extension("dap")
        end,
      },

      -- Install the vscode-js-debug adapter (needed for js based languages)
      {
        "microsoft/vscode-js-debug",
        -- After install, build it and rename the dist folder to out
        build = "npm install --legacy-peer-deps && npx gulp vsDebugServerBundle && mv dist out",
        version = "1.*",
      },

      -- Configure adapters for js based languages
      {

        "mxsdev/nvim-dap-vscode-js",
        config = function()
          ---@diagnostic disable-next-line: missing-fields
          require("dap-vscode-js").setup({
            -- node_path = "node", -- Path of node executable. Defaults to $NODE_PATH, and then "node"
            debugger_path = vim.fn.resolve(vim.fn.stdpath("data") .. "/lazy/vscode-js-debug"), -- Path to vscode-js-debug installation.
            -- debugger_cmd = { "js-debug-adapter" }, -- Command to use to launch the debug server. Takes precedence over `node_path` and `debugger_path`.
            adapters = {
              "pwa-node", -- pwa is the latest debugger for node and is called like this for legacy reasions (it comes from progressive web apps) -> https://github.com/microsoft/vscode/issues/151910#issuecomment-1153998582
              -- "pwa-chrome",
              -- "pwa-msedge",
              -- "node-terminal",
              -- "pwa-extensionHost",
            }, -- which adapters to register in nvim-dap
            -- log_file_path = "(stdpath cache)/dap_vscode_js.log" -- Path for file logging
            -- log_file_level = false -- Logging level for output to file. Set to false to disable file logging.
            -- log_console_level = vim.log.levels.ERROR -- Logging level for output to console. Set to false to disable console output.
          })

          for _, language in ipairs(js_based_languages) do
            require("dap").configurations[language] = {
              {
                name = "Launch: Default",
                type = "pwa-node",
                request = "launch",
                program = "${file}",
                cwd = vim.fn.getcwd(),
                skipFiles = {
                  "<node_internals>/**",
                },
              },
              {
                name = "Attach: Default",
                type = "pwa-node",
                request = "attach",
                processId = require("dap.utils").pick_process,
                port = function()
                  local co = coroutine.running()
                  return coroutine.create(function()
                    vim.ui.input({
                      prompt = "Port: ",
                      default = "9229",
                    }, function(port)
                      if port == nil or port == "" then
                        return
                      else
                        coroutine.resume(co, port)
                      end
                    end)
                  end)
                end,
                cwd = vim.fn.getcwd(),
                skipFiles = {
                  "<node_internals>/**",
                },
              },
            }
          end
        end,
      },
    },
    keys = {
      {
        "<leader>dB",
        function()
          require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
        end,
        desc = "Breakpoint Condition",
      },
      {
        "<leader>db",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Toggle Breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("dap").continue()
        end,
        desc = "Continue",
      },
      {
        "<leader>da",
        function()
          if vim.fn.filereadable(".vscode/launch.json") then
            local dap_vscode = require("dap.ext.vscode")
            dap_vscode.load_launchjs(nil, {
              node = js_based_languages,
              ["pwa-node"] = js_based_languages,
            })
          end
          require("dap").continue()
        end,
        desc = "Run with Args",
      },
      {
        "<leader>dC",
        function()
          require("dap").run_to_cursor()
        end,
        desc = "Run to Cursor",
      },
      {
        "<leader>dg",
        function()
          require("dap").goto_()
        end,
        desc = "Go to line (no execute)",
      },
      {
        "<leader>di",
        function()
          require("dap").step_into()
        end,
        desc = "Step Into",
      },
      {
        "<leader>dj",
        function()
          require("dap").down()
        end,
        desc = "Down",
      },
      {
        "<leader>dk",
        function()
          require("dap").up()
        end,
        desc = "Up",
      },
      {
        "<leader>dl",
        function()
          require("dap").run_last()
        end,
        desc = "Run Last",
      },
      {
        "<leader>do",
        function()
          require("dap").step_out()
        end,
        desc = "Step Out",
      },
      {
        "<leader>dO",
        function()
          require("dap").step_over()
        end,
        desc = "Step Over",
      },
      {
        "<leader>dp",
        function()
          require("dap").pause()
        end,
        desc = "Pause",
      },
      {
        "<leader>dr",
        function()
          require("dap").repl.toggle()
        end,
        desc = "Toggle REPL",
      },
      {
        "<leader>ds",
        function()
          require("dap").session()
        end,
        desc = "Session",
      },
      {
        "<leader>dt",
        function()
          require("dap").terminate()
        end,
        desc = "Terminate",
      },
      {
        "<leader>dw",
        function()
          require("dap.ui.widgets").hover()
        end,
        desc = "Widgets",
      },
    },
    config = function()
      -- configure icons
      local icons = {
        Stopped = { "󰁕 ", "DiagnosticWarn", "DapStoppedLine" },
        Breakpoint = " ",
        BreakpointCondition = " ",
        BreakpointRejected = { " ", "DiagnosticError" },
        LogPoint = ".>",
      }

      vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })

      for name, sign in pairs(icons) do
        sign = type(sign) == "table" and sign or { sign }
        vim.fn.sign_define(
          "Dap" .. name,
          { text = sign[1], texthl = sign[2] or "DiagnosticInfo", linehl = sign[3], numhl = sign[3] }
        )
      end
    end,
  },
}
