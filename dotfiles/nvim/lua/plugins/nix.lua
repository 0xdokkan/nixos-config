-- Lazy gestisce i plugin; Mason gestisce gli eseguibili esterni. Il bootstrap
-- e lazy-lock.json restano invariati. Aprire nvim DOPO nix develop / direnv:
-- l'ambiente della devshell non entra in un editor già aperto.
local uv = vim.uv or vim.loop

local function nix_executable(command)
  if type(command) ~= "string" then
    return nil
  end
  local path = vim.fn.exepath(command)
  local real = path ~= "" and uv.fs_realpath(path) or nil
  if real and real:sub(1, 11) == "/nix/store/" then
    return path
  end
end

-- NixOS oppure un ambiente con binari Nix nel PATH (anche su Arch).
-- Rilevato prima che Mason possa anteporre la propria directory bin.
local using_nix = uv.fs_stat("/etc/NIXOS") ~= nil
for directory in (vim.env.PATH or ""):gmatch("[^:]+") do
  local real = uv.fs_realpath(directory)
  if real and real:sub(1, 11) == "/nix/store/" then
    using_nix = true
    break
  end
end
if not using_nix then
  return {}
end

-- Solo pacchetti sostituibili con questi comandi. Non basta trovare
-- "codelldb": l'extra Rust usa anche le sue librerie dentro $MASON.
local tool_commands = {
  stylua = { "stylua" },
  shfmt = { "shfmt" },
  shellcheck = { "shellcheck" },
  goimports = { "goimports" },
  gofumpt = { "gofumpt" },
  gomodifytags = { "gomodifytags" },
  impl = { "impl" },
  ["golangci-lint"] = { "golangci-lint" },
  cmakelang = { "cmake-format", "cmake-lint" },
  cmakelint = { "cmakelint" },
  ["erb-formatter"] = { "erb-format" },
  ["erb-lint"] = { "erblint" },
  sqlfluff = { "sqlfluff" },
}

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- Conform/nvim-lint e gli LSP trovano prima wrapper HM e devshell.
      -- Mason resta il fallback per gli extra non ancora forniti da Nix.
      opts.PATH = "append"
      opts.ensure_installed = vim.tbl_filter(function(tool)
        local commands = tool_commands[tool]
        if not commands then
          return true
        end
        for _, command in ipairs(commands) do
          if not nix_executable(command) then
            return true
          end
        end
        return false
      end, opts.ensure_installed or {})
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      for server, server_opts in pairs(opts.servers or {}) do
        if server ~= "*" and server_opts ~= false then
          local settings = server_opts == true and {} or server_opts
          if settings.enabled ~= false then
            local defaults = vim.lsp.config[server] or {}
            local cmd = settings.cmd or defaults.cmd
            local command = type(cmd) == "table" and cmd[1] or nil
            -- jdtls ha un cmd-funzione in lspconfig, mentre LazyVim delega
            -- l'avvio a nvim-jdtls. Non sostituire altri cmd-funzione custom.
            if server == "jdtls" and settings.cmd == nil then
              command = "jdtls"
            end
            if nix_executable(command) then
              settings.mason = false
              opts.servers[server] = settings
            end
          end
        end
      end
    end,
  },
  {
    "mfussenegger/nvim-jdtls",
    optional = true,
    opts = function(_, opts)
      if not nix_executable(type(opts.cmd) == "table" and opts.cmd[1] or nil) then
        return
      end
      -- L'extra Java aggiunge questo jar solo perché Mason è abilitato,
      -- anche se jdtls viene da Nix. Lascia Lombok al wrapper/devshell Nix
      -- e conserva ogni altro argomento, inclusi eventuali javaagent custom.
      local mason_lombok = "--jvm-arg=-javaagent:" .. vim.fn.expand("$MASON/share/jdtls/lombok.jar")
      opts.cmd = vim.tbl_filter(function(argument)
        return argument ~= mason_lombok
      end, opts.cmd)
    end,
  },
}
