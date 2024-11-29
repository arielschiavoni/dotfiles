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

      local dap = require("dap")

      -- adapters
      dap.adapters["pwa-node"] = {
        type = "server",
        host = "localhost",
        port = "${port}",
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
        dap.configurations[language] = {
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
