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

## Plugins Usage

### Emmet

We disable the global mappings by default, you can active the mappings in current buffer by run `:EmmetInstall`。
