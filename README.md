# My Vim Configurations

## Setup

Base Setup

```bash
$ git clone https://github.com/graycarl/dotvim.git ~/.vim
$ cd ~/.vim
$ vim local.vim     # Some local settings
```

For Vim:

```bash
$ # Nothing else need to be done
```

For Neovim

```bash
$ cd ~/.vim
$ virtualenv -p path-to-python2 py2env
$ virtualenv -p path-to-python3 py3env
$ ln -s ~/.vim ~/.config/nvim
```

## TODO

- [x] Bind CtrlPBuffer to SPC-b
- [x] Bind CtrlPBufTag to SPC-t
- [ ] Deep study the usage of fugitive
