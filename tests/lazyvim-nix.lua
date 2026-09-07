-- Test isolati del nostro override: nessun avvio di Neovim/Lazy/Mason,
-- nessun download, modifica del profilo o accesso a plugin dell'utente.
local config_path = assert(arg[1], "usage: lua tests/lazyvim-nix.lua PATH_TO_NIX_LUA")

local function equal(actual, expected, message)
  assert(actual == expected, (message or "mismatch") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function list_equal(actual, expected)
  equal(#actual, #expected, "list length")
  for index, value in ipairs(expected) do
    equal(actual[index], value, "list entry " .. index)
  end
end

local function environment(options)
  options = options or {}
  local paths = options.executables or {}
  local realpaths = options.realpaths or {}
  _G.vim = {
    env = { PATH = options.path or "/usr/bin" },
    uv = {
      fs_stat = function(path)
        assert(path == "/etc/NIXOS")
        return options.nixos and {} or nil
      end,
      fs_realpath = function(path)
        return realpaths[path] or path
      end,
    },
    fn = {
      exepath = function(command)
        return paths[command] or (command:sub(1, 1) == "/" and paths[command]) or ""
      end,
      expand = function(path)
        equal(path, "$MASON/share/jdtls/lombok.jar")
        return "/data/mason/share/jdtls/lombok.jar"
      end,
    },
    lsp = { config = options.servers or {} },
    tbl_filter = function(predicate, list)
      local result = {}
      for _, item in ipairs(list) do
        if predicate(item) then
          result[#result + 1] = item
        end
      end
      return result
    end,
  }
  local result = {}
  for _, plugin in ipairs(dofile(config_path)) do
    assert(plugin.enabled ~= false, "must not disable plugins")
    equal(plugin.config, nil, "must retain upstream plugin setup")
    equal(plugin.build, nil, "must retain upstream plugin installation")
    result[plugin[1]] = plugin
  end
  return result
end

-- Arch normale: nessun cambio a ordine PATH, Mason o bootstrap dei plugin.
equal(next(environment()), nil)

-- NixOS: symlink del profilo risolti, tool mancanti lasciati a Mason.
local specs = environment({
  nixos = true,
  executables = {
    stylua = "/run/current-system/sw/bin/stylua",
    shfmt = "/data/mason/bin/shfmt",
    ["cmake-format"] = "/nix/store/cmake/bin/cmake-format",
    codelldb = "/nix/store/lldb/bin/codelldb",
  },
  realpaths = { ["/run/current-system/sw/bin/stylua"] = "/nix/store/stylua/bin/stylua" },
})
local mason = { ensure_installed = { "stylua", "shfmt", "shellcheck", "cmakelang", "codelldb", "unknown-tool" } }
specs["mason-org/mason.nvim"].opts(nil, mason)
equal(mason.PATH, "append")
list_equal(mason.ensure_installed, { "shfmt", "shellcheck", "cmakelang", "codelldb", "unknown-tool" })
specs["mason-org/mason.nvim"].opts(nil, {}) -- nessuna lista iniziale

-- Devshell su Arch, anche con directory symlinkata e spazi nel PATH.
specs = environment({
  path = "/project with spaces/tools/bin:/usr/bin",
  realpaths = { ["/project with spaces/tools/bin"] = "/nix/store/project/bin" },
  executables = {
    goimports = "/nix/store/go/bin/goimports",
    gofumpt = "/nix/store/go/bin/gofumpt",
    ["cmake-format"] = "/nix/store/cmake/bin/cmake-format",
    ["cmake-lint"] = "/nix/store/cmake/bin/cmake-lint",
  },
})
mason = { ensure_installed = { "goimports", "gofumpt", "cmakelang", "stylua" } }
specs["mason-org/mason.nvim"].opts(nil, mason)
list_equal(mason.ensure_installed, { "stylua" })

local java_cmd = function() end
local setup = {
  jdtls = function()
    return true
  end,
}
specs = environment({
  path = "/nix/store/devshell/bin:/usr/bin",
  executables = {
    ["lua-language-server"] = "/nix/store/lua/bin/lua-language-server",
    nil_ls = "/nix/store/wrong-name/bin/nil_ls", -- il nome server NON è il comando
    nil_renamed = "/nix/store/nil/bin/nil_renamed",
    clangd = "/nix/store/clang/bin/clangd",
    ["pyright-langserver"] = "/nix/store/pyright/bin/pyright-langserver",
    ruff = "/nix/store/ruff/bin/ruff",
    zls = "/nix/store/zig/bin/zls",
    gopls = "/usr/bin/gopls", -- Arch non viene spacciato per Nix
    jdtls = "/nix/store/jdtls/bin/jdtls",
  },
  servers = {
    lua_ls = { cmd = { "lua-language-server" } },
    nil_ls = { cmd = { "nil" } },
    pyright = { cmd = { "pyright-langserver", "--stdio" } },
    ruff = { cmd = { "ruff", "server" } },
    zls = { cmd = { "zls" } },
    gopls = { cmd = { "gopls" } },
    jdtls = { cmd = java_cmd },
    custom = { cmd = function() end },
  },
})
local lsp = {
  setup = setup,
  servers = {
    ["*"] = { capabilities = { test = true } },
    lua_ls = { settings = { Lua = { hint = { enable = true } } } },
    nil_ls = { cmd = { "nil_renamed" } },
    clangd = { cmd = { "clangd", "--background-index" } },
    pyright = true,
    ruff = {},
    zls = {},
    gopls = {},
    jdtls = {},
    custom = {},
    disabled = false,
    rust_analyzer = { enabled = false },
    missing = {},
  },
}
specs["neovim/nvim-lspconfig"].opts(nil, lsp)
for _, server in ipairs({ "lua_ls", "nil_ls", "clangd", "pyright", "ruff", "zls", "jdtls" }) do
  equal(lsp.servers[server].mason, false, server)
  equal(lsp.servers[server].enabled, nil, "server remains enabled")
end
equal(lsp.setup, setup)
equal(lsp.servers.lua_ls.settings.Lua.hint.enable, true)
list_equal(lsp.servers.clangd.cmd, { "clangd", "--background-index" })
equal(lsp.servers["*"].mason, nil)
equal(lsp.servers.gopls.mason, nil)
equal(lsp.servers.custom.mason, nil)
equal(lsp.servers.missing.mason, nil)
equal(lsp.servers.disabled, false)
equal(lsp.servers.rust_analyzer.enabled, false)
specs["neovim/nvim-lspconfig"].opts(nil, {}) -- nessun server iniziale

-- Java: togli SOLO il riferimento aggiunto dall'extra al Lombok di Mason.
local nix_jdtls = "/nix/store/jdtls/bin/jdtls"
specs = environment({ nixos = true, executables = { [nix_jdtls] = nix_jdtls } })
local java = {
  cmd = {
    nix_jdtls,
    "--jvm-arg=-javaagent:/data/mason/share/jdtls/lombok.jar",
    "--jvm-arg=-javaagent:/project/custom.jar",
    "--jvm-arg=-Xmx2G",
  },
  settings = { java = { test = true } },
}
equal(specs["mfussenegger/nvim-jdtls"].optional, true)
specs["mfussenegger/nvim-jdtls"].opts(nil, java)
list_equal(java.cmd, { nix_jdtls, "--jvm-arg=-javaagent:/project/custom.jar", "--jvm-arg=-Xmx2G" })
equal(java.settings.java.test, true)
java.cmd = { "/data/mason/bin/jdtls", "--jvm-arg=-javaagent:/data/mason/share/jdtls/lombok.jar" }
specs["mfussenegger/nvim-jdtls"].opts(nil, java)
equal(#java.cmd, 2, "Mason Java remains unchanged")

print("LazyVim Nix/Mason regression tests passed")
