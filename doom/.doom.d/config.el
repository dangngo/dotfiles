;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(setq user-full-name "Dang Ngo"
      user-mail-address "ngominh.dang96@gmail.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; (setq doom-font (font-spec :family "JetBrainsMono Nerd Font Mono" :size 13)
;;       )

(setq doom-font (font-spec :family "Iosevka Nerd Font" :size 14)
      doom-variable-pitch-font (font-spec :family "Iosevka Nerd Font" :size 14)
      )

;;(setq doom-font (font-spec :family "DejaVuSansMono Nerd Font Mono" :size 12)
;;      doom-variable-pitch-font (font-spec :family "DejaVuSansMono Nerd Font Mono" :size 12)
;;      )

;; `load-theme' function. This is the default:
(setq doom-theme 'doom-ephemeral)
;; (setq doom-theme 'doom-badger)
(setq doom-themes-treemacs-theme 'doom-colors)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
;;(setq display-line-numbers-type 'relative)
(setq display-line-numbers-type 'relative)

;; Exit without confirmation
;;(setq confirm-kill-emacs nil)

;; Map "fd" to ESC
(setq evil-escape-key-sequence "fd")

;; Start fullscreen
(add-to-list 'initial-frame-alist '(fullscreen . maximized))

;; SSH agent
(exec-path-from-shell-copy-env "SSH_AGENT_PID")
(exec-path-from-shell-copy-env "SSH_AUTH_SOCK")

;; Projects
(after! projectile
  (setq projectile-project-search-path '("~/work/repos" "~/work/opensource-repos")))

;; Org-mode
(setq org-directory "~/work/notes/")

;; Update mode-line branch name automatically
(setq auto-revert-check-vc-info t)
(setq auto-revert-interval 10)

;; Rust
(after! rustic
  (setq rustic-format-on-save t)
  (setq rustic-lsp-server 'rust-analyzer))

;; LSP-UI
(after! lsp-ui
  (setq lsp-ui-doc-position 'bottom
        lsp-ui-doc-max-width 50
        lsp-ui-sideline-enable nil
        lsp-ui-doc-enable nil))

;; Cloudformation cfn-lint mode
;; https://github.com/awkspace/doom-emacs-config/blob/dfd89cdff6204899fc49c5a2df88e71f427df0b5/config.el#L96
(define-derived-mode cfn-mode yaml-mode
  "Cloudformation"
  "Cloudformation template mode.")
(add-to-list 'magic-mode-alist
               '("\\(---\n\\)?AWSTemplateFormatVersion:" . cfn-mode))
(after! flycheck
  (flycheck-define-checker cfn-lint
    "A Cloudformation linter using cfn-python-lint.
See URL 'https://github.com/awslabs/cfn-python-lint'."
    :command ("cfn-lint"  "-i" "W3011" "-f" "parseable" source)
    :error-patterns ((warning line-start (file-name) ":" line ":" column
                              ":" (one-or-more digit) ":" (one-or-more digit) ":"
                              (id "W" (one-or-more digit)) ":" (message) line-end)
                     (error line-start (file-name) ":" line ":" column
                            ":" (one-or-more digit) ":" (one-or-more digit) ":"
                            (id "E" (one-or-more digit)) ":" (message) line-end))
    :modes (cfn-mode))
  (add-to-list 'flycheck-checkers 'cfn-lint))

;; Web-mode
;;
;; Fix *.tsx indentation
(setq web-mode-markup-indent-offset 2)
(setq web-mode-code-indent-offset 2)
;; Set Go template engine for *.tpl
(setq web-mode-engines-alist '(("go" . "\\.tpl\\'")))

;; Jenkinsfile
;;(add-to-list 'auto-mode-alist '("\\.groovy\\'" . jenkinsfile-mode))
(add-to-list 'auto-mode-alist '("\\.groovy\\'" . groovy-mode))

;; Puppet file *.pp
(add-to-list 'auto-mode-alist '("\\.pp\\'" . puppet-mode))

;; Get rid of annoying .log in git repo
(setenv "TSSERVER_LOG_FILE" "/tmp/tsserver.log")

;; Use org-superstar for better heading bullets
(add-hook 'org-mode-hook (lambda () (org-superstar-mode 1)))

(setq max-specpdl-size 32000)

;; Treemacs
;; disable width locking
(setq treemacs-width-is-initially-locked nil)
