local js_based_languages = { "javascript", "typescript", "javascriptreact", "typescriptreact" }

return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      -- virtual text for the debugger
      {
        "theHamsta/nvim-dap-virtual-text",
        opts = {},
      },
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
            "<leader>k",
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
                elements = {
                  { id = "scopes", size = 0.33 },
                  { id = "stacks", size = 0.25 },
                  { id = "watches", size = 0.25 },
                  { id = "breakpoints", size = 0.17 },
                },
                size = 0.33,
                position = "right",
              },
              {
                elements = {
                  { id = "repl", size = 0.45 },
                  { id = "console", size = 0.55 },
                },
                size = 0.27,
                position = "bottom",
              },
            },
          })

          -- setup event listeners to open/close dap-ui when debug session is started or terminated
          dap.listeners.before.attach.dapui_config = function()
            dapui.open({ reset = true })
          end
          dap.listeners.before.launch.dapui_config = function()
            dapui.open({ reset = true })
          end
          dap.listeners.before.event_terminated.dapui_config = function()
            dapui.close()
          end
          dap.listeners.before.event_exited.dapui_config = function()
            dapui.close()
          end
        end,
      },
    },
    keys = {
      {
        "<F5>",
        function()
          require("dap").continue()
        end,
        desc = "Start or Continue",
      },
      {
        -- Shift and FN keys don't works well and need a lot of extra setup
        -- https://vim.fandom.com/wiki/Mapping_fast_keycodes_in_terminal_Vim
        "<leader><F5>",
        function()
          require("dap").terminate()
        end,
        desc = "Terminate",
      },
      {
        "<F10>",
        function()
          require("dap").step_over()
        end,
        desc = "Step Over",
      },
      {
        "<F11>",
        function()
          require("dap").step_into()
        end,
        desc = "Step Into",
      },
      {
        "<leader><F11>",
        function()
          require("dap").step_out()
        end,
        desc = "Step Out",
      },
      {
        "<F6>",
        function()
          require("dap").run_to_cursor()
        end,
        desc = "Run to Cursor",
      },
      {
        "<F7>",
        function()
          require("dap").repl.toggle()
        end,
        desc = "Toggle REPL",
      },
      {
        "<F9>",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Toggle Breakpoint",
      },
      {
        "<leader><F9>",
        function()
          require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
        end,
        desc = "Breakpoint Condition",
      },
    },
    config = function()
      -- configure icons
      local icons = {
        Stopped = { "󰁕 ", "DiagnosticWarn", "DapStoppedLine" },
        Breakpoint = { " ", "DiagnosticSignError" },
        BreakpointCondition = " ",
        BreakpointRejected = { " ", "DiagnosticSignError" },
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

      local dap = require("dap")

      -- disable sending output to repl buffer, stdout is only send to the terminal buffer
      -- https://github.com/mfussenegger/nvim-dap/issues/1141
      dap.defaults.fallback.on_output = function(session, output_event) end -- this will set the option globally (all languages)
      dap.set_log_level("TRACE")

      -- adapters
      dap.adapters["pwa-node"] = {
        type = "server",
        host = "localhost",
        port = "${port}",
        restart = {
          delay = 2,
          maxAttempts = 5,
        },
        executable = {
          command = "node",
          args = {
            require("mason-registry").get_package("js-debug-adapter"):get_install_path()
              .. "/js-debug/src/dapDebugServer.js",
            "${port}",
          },
        },
      }

      -- configurations
      for _, language in ipairs(js_based_languages) do
        -- https://github.com/microsoft/vscode-js-debug/blob/main/OPTIONS.md
        dap.configurations[language] = {
          {
            name = "Launch: Default",
            type = "pwa-node",
            request = "launch",
            program = "${file}",
            cwd = vim.fn.getcwd(),
            -- see :h dap-terminal
            -- the debugee (program being debugged will be launched in a neovim terminal. It is the console dap-ui widget)
            -- the debugee can be stopped by entering insert mode in this buffer and pressing CTRL-c
            console = "integratedTerminal",
            skipFiles = {
              "<node_internals>/**",
            },
          },
          {
            name = "Attach: Default",
            type = "pwa-node",
            request = "attach",
            port = 8229,
            -- processId = require("dap.utils").pick_process,
            -- port = function()
            --   local co = coroutine.running()
            --   return coroutine.create(function()
            --     vim.ui.input({
            --       prompt = "Port: ",
            --       -- keep it untils falcon-renderer is refactored, the default should be 9229
            --       default = "8229",
            --     }, function(port)
            --       if port == nil or port == "" then
            --         return
            --       else
            --         coroutine.resume(co, port)
            --       end
            --     end)
            --   end)
            -- end,
            -- cwd = vim.fn.getcwd(),
            skipFiles = {
              "<node_internals>/**",
              "**/node_modules/**",
            },
            cwd = "${workspaceFolder}",
            resolveSourceMapLocations = {
              "**",
              "!**/node_modules/**",
            },
          },
        }
      end

      -- vscode configurations
      -- setup dap config by VsCode launch.json file
      -- local vscode = require("dap.ext.vscode")
      -- local json = require("plenary.json")
      -- vscode.json_decode = function(str)
      --   return vim.json.decode(json.json_strip_comments(str))
      -- end
      --
      -- vscode.type_to_filetypes["node"] = js_based_languages
      -- vscode.type_to_filetypes["pwa-node"] = js_based_languages
    end,
  },
}
