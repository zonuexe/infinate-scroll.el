# 📜 Emacs Infinite Scroll

## 🔎 What is this?

In Emacs, when scrolling in a buffer with `C-v` or `M-v`, it hits the beginning and end and stops scrolling.

This package detects when scrolling stops and provides implicit navigation to sibling content.

Sibling content is as follows:

 * Other files in the same directory
 * Structured files with next/previous content
   * Emacs built-in modes:
     * [`doc-view-mode`](https://www.gnu.org/software/emacs/manual/html_node/emacs/Document-View.html)
     * [`help-mode`](https://www.gnu.org/software/emacs/manual/html_node/emacs/Help-Mode.html)
     * [`Info-mode`](https://www.gnu.org/software/emacs/manual/html_mono/info.html)
   * External Lisp packages:
     * [nov.el: Major mode for reading EPUBs in Emacs](https://depp.brause.cc/nov.el/)
   * *If you know of any other packages/modes, feel free to submit an issue or PR.*

## 💾 Installation

This package requires Emacs 29.1+.

### Use package.el

```emacs-lisp
(package-vc-install
 '(infinite-scroll :url "git@github.com:zonuexe/infinite-scroll.el.git"
                   :main-file "infinate-scroll.el"))
```

## 📝 Usage

Activate `infinite-scroll-mode` (buffer-local) or `infinite-scroll-global-mode` in your `init.el`.

```emacs-lisp
;; Enable infinite scroll globally
(infinate-scroll-global-mode +1)

;; Add hook to enable only certain modes
(add-hook 'text-mode-hook #'infinate-scroll-turn-on)
```

The minor mode wraps the following commands in a keymap:

 * `scroll-up-command` / `scroll-down-command`
 * `backward-page` / `forward-page`
 * ([Evil]) `evil-scroll-down` / `evil-scroll-up`

[Evil]: https://github.com/emacs-evil/evil

## Copyright

This package is released under GPL-3.0.  See [`LICENSE`](LICENSE) file.

> Copyright (C) 2024  USAMI Kenta
>
> This program is free software; you can redistribute it and/or modify
> it under the terms of the GNU General Public License as published by
> the Free Software Foundation, either version 3 of the License, or
> (at your option) any later version.
>
> This program is distributed in the hope that it will be useful,
> but WITHOUT ANY WARRANTY; without even the implied warranty of
> MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
> GNU General Public License for more details.
>
> You should have received a copy of the GNU General Public License
> along with this program.  If not, see <https://www.gnu.org/licenses/>.
