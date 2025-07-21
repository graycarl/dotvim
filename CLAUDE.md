# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Neovim configuration using lazy.nvim as the plugin manager. The configuration follows a modular structure with Lua as the primary configuration language, while maintaining some legacy VimScript components.

### Core Structure
- `init.lua` - Main entry point that sets up lazy.nvim and loads core modules
- `lua/plugins.lua` - Central plugin definitions with version pinning
- `lua/setup/` - Plugin-specific configuration modules
- `lua/mappings.lua` - Global key mappings
- `pack/my/start/` - Custom local plugins (encrypt, vault, vimnotes)
- `pack/my/opt/` - Optional local plugins (veeva)
- `local/` - User-specific local configuration files (*.vim and *.lua)

### Plugin Management
Uses lazy.nvim with explicit version pinning for stability. Local plugins in `pack/my/` are loaded through lazy.nvim configuration rather than traditional Vim package loading.

### Key Components
- **LSP**: Mason + nvim-lspconfig with support for Lua, Python (basedpyright), and Rust
- **Completion**: nvim-cmp with LSP, buffer, and LuaSnip sources
- **Fuzzy Finding**: Telescope with fzf-native for performance
- **Git**: Fugitive + Gitsigns for comprehensive Git integration
- **Treesitter**: Syntax highlighting and code folding
- **Testing**: vim-test integration
- **Terminal**: ToggleTerm for floating terminal

## Development Commands

### Plugin Management
```bash
# Launch Neovim to trigger lazy.nvim setup if needed
nvim

# Update plugins (run inside Neovim)
:Lazy update

# Check plugin status
:Lazy
```

### LSP and Mason
```bash
# Install language servers (run inside Neovim)
:Mason

# Check LSP status
:LspInfo

# Format current buffer
:Format
```

### Testing
The configuration uses vim-test plugin. Test commands depend on the project's test framework and are automatically detected.

## Configuration Patterns

### Local Configuration
- Place user-specific configs in `local/` directory as `*.vim` or `*.lua` files
- These are automatically loaded after the main configuration
- Example: `local/base.vim` for personal settings

### Plugin Configuration
- Each plugin's setup is in `lua/setup/[plugin-name].lua`
- Complex plugins have dedicated configuration modules
- Simple plugins use inline `opts` in `lua/plugins.lua`

### Custom Plugins
- Local plugins in `pack/my/start/` are automatically loaded
- Optional plugins in `pack/my/opt/` require explicit loading
- Use `require('lazy').load({plugins={'plugin-name'}})` to load optional plugins

### Key Mappings
- Leader key: `\` (backslash)
- Local leader: `<Space>`
- Custom mappings in `lua/mappings.lua`
- LSP mappings in `lua/setup/lsp.lua`

## Language-Specific Features

### Python
- Uses basedpyright LSP server
- Supports multiple requirements files (requirements.txt, requirements.py2.txt, requirements.py3.txt)
- Includes linting via ruff, mypy, and flake8

### Rust
- rust-analyzer with clippy integration
- Cargo build scripts enabled
- Proc macros supported

### Lua
- Optimized for Neovim Lua development
- neodev.nvim for enhanced LSP support

## Folding
- Global treesitter-based folding enabled
- Foldmethod set to 'expr' with treesitter fold expression
- Custom fold text showing first line + line count
- Maximum fold nesting: 3 levels

## Special Features

### Nerd Font Support
- Conditional loading based on `NERD_FONT` environment variable
- Install with: `brew install mplus-nerd-font`
- Enable with: `export NERD_FONT=true`

### Color Scheme Switching
- Multiple color schemes available (gruvbox, everforest, onedark, etc.)
- Switch with `<F3>` (previous) and `<F4>` (next)

### Environment Setup
- Sets `LANG=en_US.UTF-8` for consistent Git output
- Configures backup directory in Neovim's state path
- Enables project-local configuration with `exrc` and `secure`