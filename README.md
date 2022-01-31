# Dotfile

## Installing

You will need `git` and GNU `stow`

Clone into your `$HOME` directory

```bash
git clone https://github.com/dangngo/dotfiles.git ~
```

Run `stow` to symlink everything or just select what you want

```bash
stow */ # Everything (the '/' ignores the README)
```

```bash
stow zsh # Just zsh config
```
