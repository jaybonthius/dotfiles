# Hel editing setup

`post-init.el` replaces Meow with [Hel](https://github.com/helheim-emacs/hel) and [hel-leader](https://github.com/helheim-emacs/hel-leader), following [Helheim's leader setup](https://github.com/helheim-emacs/helheim/blob/master/user-lisp/helheim/00-keybindings/helheim-keybindings.el) without adopting the whole framework. Both packages are pinned to the revisions tested during this migration.

## Getting started

Restart Emacs when ready; do not reload the whole `post-init.el` into a running Meow session. The existing Linux Elpaca store already has the new packages and dependencies. Other machines install them through Elpaca on their next startup. Existing buffers, workspace files, and undo history were not removed.

| Keys | Action |
| --- | --- |
| `i j k l` | Up, left, down, right |
| `h` / `H` | Insert / insert at the beginning of the line |
| `a` / `A` | Append / append at the end of the line |
| `o` / `O` | Open a line below / above |
| `v`, then movement | Extend the selection (instead of shifted Meow movement) |
| `m` | Mark text objects and surround operations |
| `y` | Hel copy, with explicit system-clipboard export through Clipetty |
| `d` / `D` | Cut / delete; ordinary deletions do not trigger Clipetty |
| `u` / `U` | Undo / redo; fine undo can separate deletion and insertion |
| `Esc` | Leave insert state, stop extending, or collapse selections |
| `s-m` | Toggle Hel in this buffer; enabling enters Normal state |
| `s-;` | Enter the existing IJKL Symex interface |

Other editing commands follow [Hel's defaults](https://github.com/helheim-emacs/hel/blob/master/docs/keybindings.org), not Meow's. For example, `J` joins lines and `s` selects matches. Symex insertion commands and Return enter Hel Insert state; Symex Escape returns to Normal state. Minibuffer editing and `C-h` help retain their existing Emacs bindings.

Ghostel, Magit (including derived modes), and Pilish chat/input buffers start with Hel disabled so native keys work. Use `s-m` if you want to select/copy their text with Hel.

## Space and which-key

In Normal/Emacs state, Space enters `hel-leader`. After 0.5 seconds, which-key shows the available continuations. Insert state still inserts ordinary spaces. Prefix menus use the same `C-c` bindings as Emacs; mode-local bindings therefore remain available. No GUI-only posframe dependency was added.

| Keys | Action |
| --- | --- |
| `SPC /` | Project ripgrep search |
| `SPC ;` | Flash jump |
| `SPC .` / `SPC ,` | Definition / return |
| `SPC s l` | Search this buffer with Consult |
| `SPC s r` / `SPC s R` | Replace text / regexp |
| `SPC s t` / `SPC s x` | Flash tree-sitter / references |
| `SPC b` / `SPC f` | Buffer / file commands |
| `SPC o` | Open terminal, project terminal, Magit, or symbols outline |
| `SPC p` / `SPC e` / `SPC l` | Existing Cape / workspace / language prefixes |
| `SPC g` / `SPC n` | Existing AI/system / note commands |
| `SPC w`, then `i j k l` | Move between windows |
| `SPC ?` | Describe bindings |
| `SPC M x` | `M-x` |
| `SPC x x s` | `C-x C-s` (save) |

The modifier prefixes are uppercase `M` for Meta and `G` for Control-Meta, so lowercase `g` and `m` do not hide existing `C-c` commands. `SPC c` adds Control to the next key; `SPC SPC` sends `C-c C-c`. Backspace edits an unfinished leader sequence, and Escape/`C-g` cancels it. The old Meow keypad and cheatsheet are gone.

## Validation and limitations

`hel-test.el` exercises the real package declarations with installation disabled: movement/insertion, leader translations and which-key pages, major-mode exclusion hooks, Symex transitions, clipboard copying, modeline state, and multiple-cursor editing/copy/undo/redo. The exclusion tests use stand-in major modes rather than launching terminals or AI sessions. The same 11 tests passed in batch mode and in a separate terminal frame on Emacs 30.2; actual Elpaca/use-package startup declarations also loaded successfully. GUI behavior and a full daemon restart were not exercised.

An upstream behavior observed at the pinned Hel revision: copying a whole-line selection with `x C` can leave the new cursor with an empty selection. Word selections such as `e C` work and are covered by the multiple-cursor regression test. No upstream command implementation was changed.

Run from the dotfiles checkout after Elpaca has installed the packages:

```sh
emacs -Q --batch \
  --eval '(dolist (dir (directory-files "~/.config/emacs/var/elpaca/builds/" t "^[^.].*")) (when (file-directory-p dir) (add-to-list (quote load-path) dir t)))' \
  -l config/emacs/hel-test.el \
  -f ert-run-tests-batch-and-exit
```

The old Meow download may remain in Elpaca's cache, but the configuration no longer installs or enables it. Rollback is a Git revert/restore of this migration followed by a normal Emacs restart; no package-cache deletion is needed.
