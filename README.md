# My Vim Configurations

## Setup

Base Setup

```sh
$ git clone https://github.com/graycarl/dotvim.git ~/.vim
$ cd ~/.vim
$ vim local.vim     # Some local settings
```

For Vim:

```sh
$ # Nothing else need to be done
```

For Neovim

```sh
$ cd ~/.vim
$ virtualenv -p path-to-python3 py3env
$ ln -s ~/.vim ~/.config/nvim
```

## TODO

- [x] Bind CtrlPBuffer to SPC-b
- [x] Bind CtrlPBufTag to SPC-t
- [x] Deep study the usage of fugitive
- [x] Improve global search tools
- [x] Table align for GFM
- [ ] Setup gO for markdown
- [ ] How to find snippet for language
- [ ] Use <Tab> to format table and jump to next column in Markdown
