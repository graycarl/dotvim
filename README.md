# My Neovim Configurations

Some key plugins:

- lazy.nvim: Plugin manager
- mason and lsp and cmp
- telescope.nvim


## About nerd font

Nerd font is disabled by default. If you want to enable nerd font display:

1. Using a nerd font;
   ```
   $ brew install mplus-nerd-font
   $ # Use this font in terminal
   ```
2. Set a environment variable;
   ```
   export NERD_FONT=true
   ```

## Lazy.nvim vs Packages

Lazy currently does not support packages. So we need to enabled local packages in `pack/my` by adding to lazy plugins:

```
{ dir = vim.fn.stdpath('config') .. '/pack/my/start/encrypt' },
{ dir = vim.fn.stdpath('config') .. '/pack/my/start/vault' },
{ dir = vim.fn.stdpath('config') .. '/pack/my/start/vimnotes' },
{ dir = vim.fn.stdpath('config') .. '/pack/my/opt/veeva', lazy=true },
```

To enable veeva plugin, you can add `require('lazy').load({plugins={'veeva'}})` in `local.lua`.
